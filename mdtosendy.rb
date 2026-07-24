#!/usr/bin/env ruby
# frozen_string_literal: true

require 'nokogiri'
require 'open3'
require 'yaml'
require 'uri'
require 'net/http'
require 'net/https'
require 'net/smtp'
require 'openssl'
require 'time'
require 'fileutils'

# Version
VERSION = '1.0.10'

# Simple CSS parser for converting CSS rules to inline styles
# Handles basic selectors and properties for email styling
class CSSParser
  def initialize(css_content)
    @rules = parse_css(css_content)
  end

  def get_style(selector)
    @rules[selector] || {}
  end

  def style_string(selector)
    styles = get_style(selector)
    return '' if styles.empty?

    styles.map { |prop, value| "#{prop}: #{value}" }.join('; ')
  end

  private

  def parse_css(css_content)
    rules = {}

    # Remove comments
    css_content = css_content.gsub(%r{/\*.*?\*/}m, '')

    # Split by closing braces to get individual rules
    css_content.scan(/([^{]+)\{([^}]+)\}/m) do |selectors, declarations|
      selectors.strip.split(',').each do |selector|
        selector = selector.strip
        next if selector.empty?

        # Parse declarations
        declarations.scan(/([^:;]+):\s*([^;]+)/) do |prop, value|
          prop = prop.strip
          value = value.strip
          next if prop.empty? || value.empty?

          # Normalize property names (convert kebab-case to camelCase for CSS, but keep as-is for inline)
          # For inline styles, we keep kebab-case
          rules[selector] ||= {}
          rules[selector][prop] = value
        end
      end
    end

    rules
  end
end

# Optional requires for CDN upload functionality
begin
  require 'aws-sdk-s3' if defined?(Gem)
rescue LoadError
  # aws-sdk-s3 not available, S3 uploads will not work
end

begin
  require 'net/scp' if defined?(Gem)
  require 'net/ssh' if defined?(Gem)
rescue LoadError
  # net-scp/net-ssh not available, SCP/SFTP uploads will not work
end

# Prompt user for confirmation
def prompt_overwrite(filename, remote_path)
  begin
    require 'io/console'
    use_getch = true
  rescue LoadError
    # Fallback to gets if io/console is not available
    use_getch = false
  end

  print "File already exists on server: #{filename}\n"
  print "If you choose not to overwrite, the existing CDN URL will be used.\n"
  print "Overwrite? (Y/n): "

  if use_getch
    # Read single character without requiring Enter
    char = $stdin.getch.downcase
    puts char # Echo the character

    # Default to yes: 'y' or Enter (which sends "\r" or "\n")
    result = char == 'y' || char == "\r" || char == "\n"
  else
    # Fallback: read line (requires Enter)
    response = $stdin.gets.chomp.downcase
    result = response.empty? || response == 'y' || response == 'yes'
  end

  result
end

# Build the public CDN URL for a remote filename
def build_cdn_url(cdn_config, remote_filename)
  cdn_url = cdn_config['url'].chomp('/')
  subdirectory = cdn_config['subdirectory'] || ''
  subdir_path = subdirectory.empty? ? '' : "#{subdirectory}/"
  "#{cdn_url}/#{subdir_path}#{remote_filename}"
end

# Check if file exists on S3
def s3_file_exists?(s3_client, bucket_name, remote_path)
  begin
    s3_client.head_object(bucket: bucket_name, key: remote_path)
    true
  rescue Aws::S3::Errors::NotFound
    false
  rescue StandardError
    false # If we can't check, assume it doesn't exist
  end
end

# Check if file exists on SFTP
def sftp_file_exists?(sftp, remote_path)
  begin
    sftp.stat!(remote_path)
    true
  rescue Net::SFTP::StatusException => e
    # SSH_FX_NO_SUCH_FILE = 2 means file doesn't exist
    # Any other error, we'll assume file doesn't exist (safer)
    false
  rescue StandardError
    false
  end
end

# Check if file exists on remote via SSH
def ssh_file_exists?(ssh, remote_path)
  begin
    # Use single quotes to safely escape the path (escape single quotes by ending quote, adding escaped quote, starting new quote)
    escaped_path = remote_path.gsub("'", "'\"'\"'")
    result = ssh.exec!("test -f '#{escaped_path}' && echo 'exists' || echo 'not_found'")
    result.to_s.strip == 'exists'
  rescue StandardError
    false
  end
end

# Upload image to S3
def upload_image_to_s3(local_path, cdn_config, markdown_file_dir)
  begin
    require 'aws-sdk-s3'
  rescue LoadError
    warn 'Error: aws-sdk-s3 gem is required for S3 uploads. Install with: gem install aws-sdk-s3'
    return nil
  end

  access_key_id = cdn_config['username']
  secret_access_key = cdn_config['password']
  bucket_name = cdn_config['path']
  subdirectory = cdn_config['subdirectory'] || ''

  unless access_key_id && secret_access_key && bucket_name
    warn 'Error: S3 configuration incomplete. Need username (access key), password (secret key), and path (bucket name)'
    return nil
  end

  # Resolve local path relative to markdown file directory
  # Try absolute path first, then relative to markdown file directory
  absolute_path = nil
  if File.exist?(local_path)
    absolute_path = File.expand_path(local_path)
  elsif File.exist?(File.join(markdown_file_dir, local_path))
    absolute_path = File.expand_path(File.join(markdown_file_dir, local_path))
  elsif File.exist?(File.expand_path(local_path))
    absolute_path = File.expand_path(local_path)
  else
    warn "Warning: Image file not found: #{local_path} (searched in: #{markdown_file_dir})"
    return nil
  end

  # Generate remote filename (start with original, add timestamp only if needed)
  filename = File.basename(absolute_path)
  name_without_ext = File.basename(filename, File.extname(filename))
  ext = File.extname(filename)

  # Determine overwrite mode: true (always), false (never), 'ask'/'prompt' (prompt), nil/not set (defaults to 'ask')
  overwrite_setting = cdn_config['overwrite']
  overwrite_always = overwrite_setting == true || overwrite_setting == 'true'
  overwrite_never = overwrite_setting == false || overwrite_setting == 'false'
  overwrite_prompt_explicit = !overwrite_setting.nil? && (overwrite_setting.to_s.downcase == 'ask' || overwrite_setting.to_s.downcase == 'prompt')
  # Default to prompt mode if not explicitly set (nil) or explicitly set to 'ask'/'prompt'
  overwrite_prompt = overwrite_setting.nil? || overwrite_prompt_explicit
  overwrite_disabled = overwrite_never

  # Start with original filename (default behavior)
  remote_filename = filename
  remote_path = subdirectory.empty? ? remote_filename : "#{subdirectory}/#{remote_filename}"

  # Determine content type from file extension
  content_type_map = {
    '.jpg' => 'image/jpeg',
    '.jpeg' => 'image/jpeg',
    '.png' => 'image/png',
    '.gif' => 'image/gif',
    '.webp' => 'image/webp',
    '.svg' => 'image/svg+xml',
    '.bmp' => 'image/bmp',
    '.ico' => 'image/x-icon',
    '.tiff' => 'image/tiff',
    '.tif' => 'image/tiff'
  }
  content_type = content_type_map[ext.downcase] || 'image/jpeg' # Default to jpeg if unknown

  begin
    # Get region from config or use default
    region = cdn_config['region'] || 'us-east-1'

    s3_client = Aws::S3::Client.new(
      access_key_id: access_key_id,
      secret_access_key: secret_access_key,
      region: region
    )

    # Check if file exists and handle based on overwrite mode
    if s3_file_exists?(s3_client, bucket_name, remote_path)
      if overwrite_prompt
        # Prompt for confirmation
        unless prompt_overwrite(filename, remote_path)
          puts "Skipping upload (using existing): #{filename}"
          return build_cdn_url(cdn_config, remote_filename)
        end
        # User confirmed, proceed with overwrite using original filename
      elsif overwrite_disabled
        # Overwrite disabled and file exists - add timestamp to avoid overwriting
        timestamp = Time.now.strftime('%Y%m%d%H%M%S')
        remote_filename = "#{name_without_ext}_#{timestamp}#{ext}"
        remote_path = subdirectory.empty? ? remote_filename : "#{subdirectory}/#{remote_filename}"
      end
      # If overwrite_always, just proceed with overwrite (no prompt, no timestamp)
    end

    File.open(absolute_path, 'rb') do |file|
      upload_params = {
        bucket: bucket_name,
        key: remote_path,
        body: file,
        content_type: content_type,
        cache_control: 'public, max-age=31536000' # Cache for 1 year
      }
      # Set ACL if configured, otherwise try to make it public-readable
      # Note: If bucket has ACLs disabled, you'll need a bucket policy instead
      if cdn_config['acl']
        upload_params[:acl] = cdn_config['acl']
      else
        # Try to set public-read ACL (will fail if ACLs are disabled)
        upload_params[:acl] = 'public-read'
      end

      s3_client.put_object(upload_params)
    rescue Aws::S3::Errors::AccessDenied => e
      # ACL might be disabled, warn user but continue
      warn "Warning: Could not set ACL (bucket may have ACLs disabled): #{e.message}"
      warn "  Ensure your S3 bucket policy allows public read access for email clients"
    end

    # Construct CDN URL
    build_cdn_url(cdn_config, remote_filename)
  rescue StandardError => e
    warn "Error uploading to S3: #{e.message}"
    nil
  end
end

# Upload image via SCP
def upload_image_via_scp(local_path, cdn_config, markdown_file_dir)
  begin
    require 'net/scp'
    require 'net/ssh'
  rescue LoadError
    warn 'Error: net-scp and net-ssh gems are required for SCP uploads. Install with: gem install net-scp net-ssh'
    return nil
  rescue NotImplementedError => e
    if e.message.include?('ed25519')
      warn 'Error: ed25519 SSH key support requires additional gems.'
      warn '  Install with: gem install ed25519 bcrypt_pbkdf'
      warn '  Or run: bundle install'
      return nil
    end
    raise
  end

  hostname = cdn_config['hostname']
  username = cdn_config['username']
  password = cdn_config['password']
  remote_path_base = cdn_config['path'] || '/'
  subdirectory = cdn_config['subdirectory'] || ''
  port = cdn_config['port'] || 22

  unless hostname
    warn 'Error: SCP configuration incomplete. Need hostname (can be SSH config alias)'
    return nil
  end

  # Build SSH connection options
  # Net::SSH will automatically read from ~/.ssh/config if hostname is an alias
  # It will use username, hostname, port, and identity files from SSH config if not specified
  ssh_options = {}
  ssh_options[:password] = password if password
  ssh_options[:port] = port if port && port != 22
  # Use system known_hosts file for host key verification
  # This allows Net::SSH to verify against ~/.ssh/known_hosts like regular SSH does
  known_hosts_file = File.join(Dir.home, '.ssh', 'known_hosts')
  if File.exist?(known_hosts_file)
    begin
      ssh_options[:known_hosts] = Net::SSH::KnownHosts.new([known_hosts_file])
    rescue StandardError
      # If there's an issue with known_hosts, fall back to accepting new hosts
      ssh_options[:verify_host_key] = :accept_new_or_local_tunnel
    end
  else
    # If known_hosts doesn't exist, accept new hosts (like SSH does on first connection)
    ssh_options[:verify_host_key] = :accept_new_or_local_tunnel
  end

  # Resolve local path relative to markdown file directory
  # Try absolute path first, then relative to markdown file directory
  absolute_path = nil
  if File.exist?(local_path)
    absolute_path = File.expand_path(local_path)
  elsif File.exist?(File.join(markdown_file_dir, local_path))
    absolute_path = File.expand_path(File.join(markdown_file_dir, local_path))
  elsif File.exist?(File.expand_path(local_path))
    absolute_path = File.expand_path(local_path)
  else
    warn "Warning: Image file not found: #{local_path} (searched in: #{markdown_file_dir})"
    return nil
  end

  # Generate remote filename (start with original, add timestamp only if needed)
  filename = File.basename(absolute_path)
  name_without_ext = File.basename(filename, File.extname(filename))
  ext = File.extname(filename)

  # Determine overwrite mode: true (always), false (never), 'ask'/'prompt' (prompt), nil/not set (defaults to 'ask')
  overwrite_setting = cdn_config['overwrite']
  overwrite_always = overwrite_setting == true || overwrite_setting == 'true'
  overwrite_never = overwrite_setting == false || overwrite_setting == 'false'
  overwrite_prompt_explicit = !overwrite_setting.nil? && (overwrite_setting.to_s.downcase == 'ask' || overwrite_setting.to_s.downcase == 'prompt')
  # Default to prompt mode if not explicitly set (nil) or explicitly set to 'ask'/'prompt'
  overwrite_prompt = overwrite_setting.nil? || overwrite_prompt_explicit
  overwrite_disabled = overwrite_never

  # Start with original filename (default behavior)
  remote_filename = filename
  remote_dir = subdirectory.empty? ? remote_path_base : "#{remote_path_base}/#{subdirectory}".gsub(%r{//+}, '/')
  remote_path = "#{remote_dir}/#{remote_filename}".gsub(%r{//+}, '/')

  begin
    # Net::SSH will use SSH config if hostname is an alias (like 'dh')
    # It will automatically use keys, username, hostname, and port from ~/.ssh/config
    # If username is provided, use it; otherwise let SSH config provide it
    Net::SSH.start(hostname, username, ssh_options) do |ssh|
      # Expand ~ in remote directory path if present
      # Get the remote home directory and expand ~
      if remote_dir.start_with?('~/')
        home_result = ssh.exec!("echo $HOME")
        home_dir = home_result.to_s.strip
        expanded_remote_dir = remote_dir.sub(/^~/, home_dir)
        expanded_remote_path = remote_path.sub(/^~/, home_dir)
      else
        expanded_remote_dir = remote_dir
        expanded_remote_path = remote_path
      end

      # Check if file exists and handle based on overwrite mode
      if ssh_file_exists?(ssh, expanded_remote_path)
        if overwrite_prompt
          # Prompt for confirmation
          unless prompt_overwrite(filename, expanded_remote_path)
            puts "Skipping upload (using existing): #{filename}"
            return build_cdn_url(cdn_config, remote_filename)
          end
          # User confirmed, proceed with overwrite using original filename
        elsif overwrite_disabled
          # Overwrite disabled and file exists - add timestamp to avoid overwriting
          timestamp = Time.now.strftime('%Y%m%d%H%M%S')
          remote_filename = "#{name_without_ext}_#{timestamp}#{ext}"
          remote_path = "#{remote_dir}/#{remote_filename}".gsub(%r{//+}, '/')
          # Re-expand path with new filename
          if remote_dir.start_with?('~/')
            expanded_remote_path = remote_path.sub(/^~/, home_dir)
          else
            expanded_remote_path = remote_path
          end
        end
        # If overwrite_always, just proceed with overwrite (no prompt, no timestamp)
      end

      # Ensure remote directory exists
      result = ssh.exec!("mkdir -p #{expanded_remote_dir}")
      unless result.exitstatus == 0
        warn "Warning: Could not create remote directory: #{expanded_remote_dir} (exit code: #{result.exitstatus})"
        warn "  Output: #{result}" unless result.to_s.empty?
        raise "Failed to create remote directory"
      end

      # Upload file
      begin
        ssh.scp.upload!(absolute_path, expanded_remote_path)
      rescue Net::SCP::Error => e
        warn "SCP upload failed: #{e.message}"
        warn "  Local file: #{absolute_path}"
        warn "  Remote path: #{expanded_remote_path}"
        raise
      end
    end

    build_cdn_url(cdn_config, remote_filename)
  rescue NotImplementedError => e
    if e.message.include?('ed25519')
      warn 'Error: ed25519 SSH key support requires additional gems.'
      warn '  Install with: gem install ed25519 bcrypt_pbkdf'
      warn '  Or run: bundle install'
      return nil
    end
    raise
  rescue Net::SSH::HostKeyMismatch => e
    warn "Error: SSH host key fingerprint mismatch for #{hostname}"
    warn "  Fingerprint: #{e.fingerprint}"
    warn "  Host: #{e.host}"
    warn "  This usually means the server's key has changed or there's a mismatch in known_hosts"
    warn "  To fix: Remove the old entry from ~/.ssh/known_hosts or update it with: ssh-keygen -R #{e.host || hostname}"
    nil
  rescue Net::SCP::Error => e
    warn "Error uploading via SCP: #{e.message}"
    warn "  This usually indicates a problem with the remote path, permissions, or directory creation"
    warn "  Check that the remote directory exists and is writable"
    nil
  rescue StandardError => e
    warn "Error uploading via SCP: #{e.message}"
    warn "  Local file: #{absolute_path}" if defined?(absolute_path)
    warn "  Remote path: #{remote_path}" if defined?(remote_path)
    nil
  end
end

# Upload image via SFTP
def upload_image_via_sftp(local_path, cdn_config, markdown_file_dir)
  begin
    require 'net/ssh'
    require 'net/sftp'
  rescue LoadError
    warn 'Error: net-ssh gem is required for SFTP uploads. Install with: gem install net-ssh'
    return nil
  rescue NotImplementedError => e
    if e.message.include?('ed25519')
      warn 'Error: ed25519 SSH key support requires additional gems.'
      warn '  Install with: gem install ed25519 bcrypt_pbkdf'
      warn '  Or run: bundle install'
      return nil
    end
    raise
  end

  hostname = cdn_config['hostname']
  username = cdn_config['username']
  password = cdn_config['password']
  remote_path_base = cdn_config['path'] || '/'
  subdirectory = cdn_config['subdirectory'] || ''
  port = cdn_config['port'] || 22

  unless hostname
    warn 'Error: SFTP configuration incomplete. Need hostname (can be SSH config alias)'
    return nil
  end

  # Build SSH connection options
  # Net::SSH will automatically read from ~/.ssh/config if hostname is an alias
  # It will use username, hostname, port, and identity files from SSH config if not specified
  ssh_options = {}
  ssh_options[:password] = password if password
  ssh_options[:port] = port if port && port != 22
  # Use system known_hosts file for host key verification
  # This allows Net::SSH to verify against ~/.ssh/known_hosts like regular SSH does
  known_hosts_file = File.join(Dir.home, '.ssh', 'known_hosts')
  if File.exist?(known_hosts_file)
    begin
      ssh_options[:known_hosts] = Net::SSH::KnownHosts.new([known_hosts_file])
    rescue StandardError
      # If there's an issue with known_hosts, fall back to accepting new hosts
      ssh_options[:verify_host_key] = :accept_new_or_local_tunnel
    end
  else
    # If known_hosts doesn't exist, accept new hosts (like SSH does on first connection)
    ssh_options[:verify_host_key] = :accept_new_or_local_tunnel
  end

  # Resolve local path relative to markdown file directory
  # Try absolute path first, then relative to markdown file directory
  absolute_path = nil
  if File.exist?(local_path)
    absolute_path = File.expand_path(local_path)
  elsif File.exist?(File.join(markdown_file_dir, local_path))
    absolute_path = File.expand_path(File.join(markdown_file_dir, local_path))
  elsif File.exist?(File.expand_path(local_path))
    absolute_path = File.expand_path(local_path)
  else
    warn "Warning: Image file not found: #{local_path} (searched in: #{markdown_file_dir})"
    return nil
  end

  # Generate remote filename (start with original, add timestamp only if needed)
  filename = File.basename(absolute_path)
  name_without_ext = File.basename(filename, File.extname(filename))
  ext = File.extname(filename)

  # Determine overwrite mode: true (always), false (never), 'ask'/'prompt' (prompt), nil/not set (defaults to 'ask')
  overwrite_setting = cdn_config['overwrite']
  overwrite_always = overwrite_setting == true || overwrite_setting == 'true'
  overwrite_never = overwrite_setting == false || overwrite_setting == 'false'
  overwrite_prompt_explicit = !overwrite_setting.nil? && (overwrite_setting.to_s.downcase == 'ask' || overwrite_setting.to_s.downcase == 'prompt')
  # Default to prompt mode if not explicitly set (nil) or explicitly set to 'ask'/'prompt'
  overwrite_prompt = overwrite_setting.nil? || overwrite_prompt_explicit
  overwrite_disabled = overwrite_never

  # Start with original filename (default behavior)
  remote_filename = filename
  remote_dir = subdirectory.empty? ? remote_path_base : "#{remote_path_base}/#{subdirectory}".gsub(%r{//+}, '/')
  remote_path = "#{remote_dir}/#{remote_filename}".gsub(%r{//+}, '/')

  begin
    # Net::SSH will use SSH config if hostname is an alias (like 'dh')
    # It will automatically use keys, username, hostname, and port from ~/.ssh/config
    # If username is provided, use it; otherwise let SSH config provide it
    Net::SSH.start(hostname, username, ssh_options) do |ssh|
      ssh.sftp.connect do |sftp|
        # Check if file exists and handle based on overwrite mode
        if sftp_file_exists?(sftp, remote_path)
          if overwrite_prompt
            # Prompt for confirmation
            unless prompt_overwrite(filename, remote_path)
              puts "Skipping upload (using existing): #{filename}"
              return build_cdn_url(cdn_config, remote_filename)
            end
            # User confirmed, proceed with overwrite using original filename
          elsif overwrite_disabled
            # Overwrite disabled and file exists - add timestamp to avoid overwriting
            timestamp = Time.now.strftime('%Y%m%d%H%M%S')
            remote_filename = "#{name_without_ext}_#{timestamp}#{ext}"
            remote_path = "#{remote_dir}/#{remote_filename}".gsub(%r{//+}, '/')
          end
          # If overwrite_always, just proceed with overwrite (no prompt, no timestamp)
        end

        # Ensure remote directory exists
        begin
          sftp.mkdir!(remote_dir)
        rescue Net::SFTP::StatusException => e
          # Directory might already exist, ignore error
          raise e unless e.code == 4 # SSH_FX_FAILURE
        end

        # Upload file
        sftp.upload!(absolute_path, remote_path)
      end
    end

    build_cdn_url(cdn_config, remote_filename)
  rescue NotImplementedError => e
    if e.message.include?('ed25519')
      warn 'Error: ed25519 SSH key support requires additional gems.'
      warn '  Install with: gem install ed25519 bcrypt_pbkdf'
      warn '  Or run: bundle install'
      return nil
    end
    raise
  rescue Net::SSH::HostKeyMismatch => e
    warn "Error: SSH host key fingerprint mismatch for #{hostname}"
    warn "  Fingerprint: #{e.fingerprint}"
    warn "  Host: #{e.host}"
    warn "  This usually means the server's key has changed or there's a mismatch in known_hosts"
    warn "  To fix: Remove the old entry from ~/.ssh/known_hosts or update it with: ssh-keygen -R #{e.host || hostname}"
    nil
  rescue StandardError => e
    warn "Error uploading via SFTP: #{e.message}"
    nil
  end
end

# Check if a URL is a local file path
def local_image?(url)
  return false if url.nil? || url.strip.empty?

  # Check if it"s a URL protocol (http://, https://, //, data:, mailto:, etc.)"
  return false if url =~ %r{^[a-z][a-z0-9+.-]*://}i # Any protocol (http://, ftp://, etc.)
  return false if url =~ %r{^//} # Protocol-relative URL (//example.com/image.jpg)
  return false if url =~ /^data:/i # Data URI
  return false if url =~ /^mailto:/i # Mailto link
  return false if url =~ /^#/ # Anchor link

  # Check if it looks like a local file path
  # Starts with / (absolute path), ./ (relative), ../ (parent relative), or just a filename
  # Also check for Windows paths (C:\, D:\, etc.)
  url.strip =~ %r{^(/|\./|\.\./|[a-z]:[/\\]|^[^/\\:]+\.(jpg|jpeg|png|gif|webp|svg|bmp|ico))}i
end

# Upload local images in HTML and replace URLs
def upload_and_replace_images(html_content, cdn_config, markdown_file_dir)
  return html_content unless cdn_config && cdn_config['url'] && cdn_config['type']

  doc = Nokogiri::HTML::DocumentFragment.parse(html_content)
  uploaded_count = 0

  doc.css('img').each do |img|
    src = img['src']
    next unless src && local_image?(src)

    # Determine upload method based on type
    cdn_url = case cdn_config['type'].downcase
              when 's3'
                upload_image_to_s3(src, cdn_config, markdown_file_dir)
              when 'scp'
                upload_image_via_scp(src, cdn_config, markdown_file_dir)
              when 'sftp'
                upload_image_via_sftp(src, cdn_config, markdown_file_dir)
              else
                warn "Error: Unknown CDN type: #{cdn_config['type']}. Supported types: s3, scp, sftp"
                next
              end

    next unless cdn_url

    img['src'] = cdn_url
    uploaded_count += 1
    puts "CDN image: #{src} -> #{cdn_url}"
  end

  puts "Resolved #{uploaded_count} image(s) to CDN URLs" if uploaded_count > 0
  doc.to_html
end

# Get config directory
def config_dir
  File.join(Dir.home, '.config', 'mdtosendy')
end

# Get templates directory
def templates_dir
  File.join(config_dir, 'templates')
end

# Get template directory for a specific template name
def template_dir(template_name)
  File.join(templates_dir, template_name)
end

# Get default template directory
def default_template_dir
  template_dir('default')
end

# Migrate old template files to templates/default for backwards compatibility
def migrate_old_template_files
  old_template_file = File.join(config_dir, 'email-template.html')
  old_styles_file = File.join(config_dir, 'styles.css')

  # Check if old files exist and default template doesn't exist yet
  return unless (File.exist?(old_template_file) || File.exist?(old_styles_file)) && !Dir.exist?(default_template_dir)

  puts 'Migrating template files to new template system...'

  # Create templates directory if it doesn't exist
  FileUtils.mkdir_p(templates_dir)

  # Create default template directory
  FileUtils.mkdir_p(default_template_dir)

  # Move template file if it exists
  if File.exist?(old_template_file)
    new_template_file = File.join(default_template_dir, 'email-template.html')
    FileUtils.mv(old_template_file, new_template_file)
    puts "  Moved #{old_template_file} -> #{new_template_file}"
  end

  # Move styles file if it exists
  if File.exist?(old_styles_file)
    new_styles_file = File.join(default_template_dir, 'styles.css')
    FileUtils.mv(old_styles_file, new_styles_file)
    puts "  Moved #{old_styles_file} -> #{new_styles_file}"
  end

  # Create blank config.yml for default template
  default_config_file = File.join(default_template_dir, 'config.yml')
  unless File.exist?(default_config_file)
    config_content = "# Template-specific configuration\n" \
                     "# This file overrides values from ~/.config/mdtosendy/config.yml\n" \
                     "# Leave empty to use base config only\n"
    File.write(default_config_file, config_content)
    puts "  Created blank config file: #{default_config_file}"
  end

  puts "\nNote: Template files have been moved to #{default_template_dir}/"
  puts "You can now create additional templates in #{templates_dir}/"
  puts "Use --template NAME to specify a template, or --create-template NAME to create a new one.\n\n"
end

# Ensure default template exists, create from example files if needed
def ensure_default_template_exists
  return if Dir.exist?(default_template_dir)

  # Check if we're in the source directory and example files exist
  source_dir = File.dirname(File.expand_path(__FILE__))
  example_template = File.join(source_dir, 'email-template.html')
  example_styles = File.join(source_dir, 'styles.example.css')

  # Create templates directory if it doesn't exist
  FileUtils.mkdir_p(templates_dir)
  FileUtils.mkdir_p(default_template_dir)

  # Copy example files if they exist
  if File.exist?(example_template)
    default_template_file = File.join(default_template_dir, 'email-template.html')
    FileUtils.cp(example_template, default_template_file)
  end

  return unless File.exist?(example_styles)

  default_styles_file = File.join(default_template_dir, 'styles.css')
  FileUtils.cp(example_styles, default_styles_file)

  # Create blank config.yml for default template
  default_config_file = File.join(default_template_dir, 'config.yml')
  return if File.exist?(default_config_file)

  config_content = "# Template-specific configuration\n" \
                   "# This file overrides values from ~/.config/mdtosendy/config.yml\n" \
                   "# Leave empty to use base config only\n"
  File.write(default_config_file, config_content)
end

# Create a new template from default
def create_template(template_name, parent_name = nil)
  if template_name.nil? || template_name.strip.empty?
    warn 'Error: Template name is required for --create-template'
    exit 1
  end

  # Sanitize template name (remove invalid characters)
  sanitized_name = template_name.strip.gsub(/[^a-zA-Z0-9._-]/, '')
  if sanitized_name != template_name.strip
    warn "Warning: Template name sanitized from '#{template_name}' to '#{sanitized_name}'"
  end

  new_template_dir = template_dir(sanitized_name)

  if Dir.exist?(new_template_dir)
    warn "Error: Template '#{sanitized_name}' already exists at #{new_template_dir}"
    exit 1
  end

  # If parent is specified, create child template
  if parent_name
    sanitized_parent = parent_name.strip.gsub(/[^a-zA-Z0-9._-]/, '')
    parent_dir = template_dir(sanitized_parent)

    unless Dir.exist?(parent_dir)
      warn "Error: Parent template '#{sanitized_parent}' not found at #{parent_dir}"
      exit 1
    end

    # Create new template directory
    FileUtils.mkdir_p(new_template_dir)

    # Create config.yml with parent reference and commented parent config
    parent_config_file = File.join(parent_dir, 'config.yml')
    new_config_file = File.join(new_template_dir, 'config.yml')

    config_content = "parent: #{sanitized_parent}\n\n"

    # Add parent config as comments if it exists
    if File.exist?(parent_config_file)
      parent_config_content = File.read(parent_config_file)
      config_content += "# Parent template config (commented out):\n"
      parent_config_content.each_line do |line|
        config_content += "# #{line}"
      end
    end

    File.write(new_config_file, config_content)
    puts "Created child template '#{sanitized_name}' with parent '#{sanitized_parent}'"
    puts "Config file: #{new_config_file}"
    puts "\nTemplate '#{sanitized_name}' created successfully!"
    puts 'Edit the config file to override parent settings.'
    puts "Add HTML/CSS files to override parent's files, or leave them out to use parent's.\n"
    return
  end

  # Ensure default template exists first
  default_dir = default_template_dir
  unless Dir.exist?(default_dir)
    warn "Error: Default template not found. Please ensure #{default_dir} exists."
    exit 1
  end

  # Create new template directory
  FileUtils.mkdir_p(new_template_dir)

  # Copy default template files
  default_template_file = File.join(default_dir, 'email-template.html')
  default_styles_file = File.join(default_dir, 'styles.css')

  if File.exist?(default_template_file)
    new_template_file = File.join(new_template_dir, 'email-template.html')
    FileUtils.cp(default_template_file, new_template_file)
    puts "Created template file: #{new_template_file}"
  end

  if File.exist?(default_styles_file)
    new_styles_file = File.join(new_template_dir, 'styles.css')
    FileUtils.cp(default_styles_file, new_styles_file)
    puts "Created styles file: #{new_styles_file}"
  end

  # Copy or create config.yml
  default_config_file = File.join(default_dir, 'config.yml')
  new_config_file = File.join(new_template_dir, 'config.yml')
  if File.exist?(default_config_file)
    FileUtils.cp(default_config_file, new_config_file)
    puts "Created config file: #{new_config_file}"
  else
    config_content = "# Template-specific configuration\n" \
                     "# This file overrides values from ~/.config/mdtosendy/config.yml\n" \
                     "# Leave empty to use base config only\n"
    File.write(new_config_file, config_content)
    puts "Created blank config file: #{new_config_file}"
  end

  puts "\nTemplate '#{sanitized_name}' created successfully!"
  puts "Edit the files in #{new_template_dir}/ to customize your template."
  puts "Use --template #{sanitized_name} to use this template.\n"
end

# Load template-specific configuration from template directory
# Handles parent templates recursively
def load_template_config(template_name, visited = [])
  # Prevent infinite loops
  if visited.include?(template_name)
    warn "Warning: Circular parent reference detected in template '#{template_name}'"
    return {}
  end
  visited << template_name

  template_config_file = File.join(template_dir(template_name), 'config.yml')

  return {} unless File.exist?(template_config_file)

  template_config = YAML.safe_load(File.read(template_config_file)) || {}

  # If this template has a parent, load parent config first and merge
  if template_config['parent']
    parent_name = template_config['parent']
    parent_config = load_template_config(parent_name, visited)
    # Merge parent config first, then child config overrides
    template_config = deep_merge(parent_config, template_config)
  end

  template_config
rescue StandardError => e
  warn "Warning: Error loading template config from #{template_config_file}: #{e.message}"
  {}
end

# Load base configuration from config.yml
def load_base_config
  config_file = File.join(config_dir, 'config.yml')

  unless File.exist?(config_file)
    warn "Error: Configuration file not found: #{config_file}"
    warn "Please create #{config_file} with your configuration."
    warn 'You can use config.example.yml as a template.'
    exit 1
  end

  YAML.safe_load(File.read(config_file)) || {}
rescue StandardError => e
  warn "Error loading configuration: #{e.message}"
  exit 1
end

# Load configuration, merging base config with template-specific config
# Template config overrides base config
def load_config(template_name = 'default')
  base_config = load_base_config
  template_config = load_template_config(template_name)

  merged = deep_merge(base_config, template_config)
  if merged['cdn']
    merged = merged.dup
    merged['cdn'] = sanitize_merged_cdn_config(merged['cdn'], template_config['cdn'])
  end
  merged
end

# Find template file (HTML or CSS) with parent fallback
# Returns the file path if found, nil otherwise
def find_template_file(template_name, filename, visited = [])
  # Prevent infinite loops
  return nil if visited.include?(template_name)

  visited << template_name

  template_file = File.join(template_dir(template_name), filename)
  return template_file if File.exist?(template_file)

  # Check parent template if file doesn't exist
  template_config_file = File.join(template_dir(template_name), 'config.yml')
  if File.exist?(template_config_file)
    begin
      template_config = YAML.safe_load(File.read(template_config_file)) || {}
      return find_template_file(template_config['parent'], filename, visited) if template_config['parent']
    rescue StandardError
      # Ignore errors, just return nil
    end
  end

  nil
end

# Load CSS styles from styles.css
def load_styles(template_name = 'default')
  config = load_config(template_name)
  styles_filename = config.dig('paths', 'styles_file') || 'styles.css'
  styles_file = find_template_file(template_name, styles_filename)

  unless styles_file && File.exist?(styles_file)
    warn "Error: Styles file not found: #{styles_filename}"
    warn "Please create #{File.join(template_dir(template_name), styles_filename)} with your styles."
    if template_name == 'default'
      warn 'You can use styles.example.css as a template.'
    else
      warn "Or create a new template with: #{$0} --create-template #{template_name}"
    end
    exit 1
  end

  CSSParser.new(File.read(styles_file))
rescue StandardError => e
  warn "Error loading styles: #{e.message}"
  exit 1
end

# Convert Markdown to HTML
def markdown_to_html(markdown_content, processor = 'apex')
  # Split processor string into command and arguments
  processor_parts = processor.strip.split(/\s+/)
  command = processor_parts[0]
  args = processor_parts[1..-1] || []

  # Execute with arguments
  stdout, stderr, status = Open3.capture3(command, *args, stdin_data: markdown_content)

  unless status.success?
    warn "Error converting Markdown: #{stderr}"
    exit 1
  end

  stdout
end

# Apply inline styles to HTML elements for email compatibility
def apply_email_styles(html_content, styles, link_selector: 'a')
  doc = Nokogiri::HTML::DocumentFragment.parse(html_content)

  # Helper to merge styles
  def merge_styles(existing, new_styles)
    existing_hash = existing ? existing.split(';').map { |s| s.split(':').map(&:strip) }.to_h : {}
    new_hash = new_styles.is_a?(String) ? {} : new_styles
    merged = existing_hash.merge(new_hash)
    merged.map { |k, v| "#{k}: #{v}" }.join('; ')
  end

  # Helper to extract margin/padding and convert to table cell padding
  # Returns the padding value to use for the td, and a filtered style string without margin/padding
  def extract_spacing_for_table(selector, styles, default_padding = '0 0 20px 0')
    # First check for explicit td selector (backwards compatibility)
    td_style = styles.get_style("#{selector} td")
    if td_style['padding']
      element_style = styles.get_style(selector)
      # Remove margin/padding from element style
      filtered_style = element_style.reject { |k, _v| %w[margin padding].include?(k.downcase) }
      return [td_style['padding'], filtered_style]
    end

    # Extract margin and padding from element style
    element_style = styles.get_style(selector)
    margin = element_style['margin'] || element_style['margin-top'] || element_style['margin-bottom'] || nil
    padding = element_style['padding'] || element_style['padding-top'] || element_style['padding-bottom'] || nil

    # Convert margin to padding (margins don't work well in email tables)
    # Combine margin and padding if both exist
    final_padding = if margin && padding
                      # Combine margin and padding - add them together
                      combine_spacing(margin, padding)
                    elsif margin
                      margin
                    elsif padding
                      padding
                    else
                      default_padding
                    end

    # Remove margin and padding from element style
    filtered_style = element_style.reject do |k, _v|
      %w[margin padding margin-top margin-bottom margin-left margin-right padding-top padding-bottom padding-left
         padding-right].include?(k.downcase)
    end

    [final_padding, filtered_style]
  end

  # Helper to combine margin and padding values
  # Simple approach: if both are single values, add them; otherwise use margin
  def combine_spacing(margin, _padding)
    # For now, prefer margin over padding if both exist
    # This could be enhanced to actually add numeric values
    margin
  end

  # Style h1 elements
  doc.css('h1').reverse.each do |h1|
    td_padding, filtered_style = extract_spacing_for_table('h1', styles, '0 0 20px 0')
    h1['style'] = filtered_style.map { |k, v| "#{k}: #{v}" }.join('; ')

    table_html = <<~HTML
      <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%">
        <tr>
          <td style="padding: #{td_padding};">
            #{h1.to_html}
          </td>
        </tr>
      </table>
    HTML

    h1.replace(table_html)
  end

  # Style h2 elements
  doc.css('h2').reverse.each do |h2|
    td_padding, filtered_style = extract_spacing_for_table('h2', styles, '0 0 20px 0')
    h2['style'] = filtered_style.map { |k, v| "#{k}: #{v}" }.join('; ')

    table_html = <<~HTML
      <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%">
        <tr>
          <td style="padding: #{td_padding};">
            #{h2.to_html}
          </td>
        </tr>
      </table>
    HTML

    h2.replace(table_html)
  end

  # Style h3 elements
  doc.css('h3').reverse.each do |h3|
    td_padding, filtered_style = extract_spacing_for_table('h3', styles, '0 0 15px 0')
    h3['style'] = filtered_style.map { |k, v| "#{k}: #{v}" }.join('; ')

    table_html = <<~HTML
      <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%">
        <tr>
          <td style="padding: #{td_padding};">
            #{h3.to_html}
          </td>
        </tr>
      </table>
    HTML

    h3.replace(table_html)
  end

  # Style paragraph elements
  doc.css('p').reverse.each do |p|
    # Skip if already inside a styled td
    next if p.ancestors.any? { |a| a.name == 'td' && a['style']&.include?('padding') }

    td_padding, filtered_style = extract_spacing_for_table('p', styles, '0 0 20px 0')
    p_style_filtered = filtered_style.map { |k, v| "#{k}: #{v}" }.join('; ')

    table_html = <<~HTML
      <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%">
        <tr>
          <td style="padding: #{td_padding}; #{p_style_filtered};">
            #{p.inner_html}
          </td>
        </tr>
      </table>
    HTML

    p.replace(table_html)
  end

  # Convert lists to table format
  doc.css('ul, ol').reverse.each do |list|
    # Skip if already inside a styled td
    next if list.ancestors.any? { |a| a.name == 'td' && a['style']&.include?('padding') }

    list_items = list.css('li')
    is_ordered = list.name == 'ol'

    styles.get_style('li.bullet')
    styles.get_style('li.content')

    # Extract spacing from list element (ul or ol)
    list_selector = list.name
    list_td_padding, list_filtered_style = extract_spacing_for_table(list_selector, styles, '0 0 10px 0')
    list_style = list_filtered_style.map { |k, v| "#{k}: #{v}" }.join('; ')

    # Build table rows for each list item
    rows_html = list_items.each_with_index.map do |li, index|
      bullet = is_ordered ? "#{index + 1}." : '•'
      bullet_style_str = styles.style_string('li.bullet')
      content_style_str = styles.style_string('li.content')

      <<~HTML
        <tr>
          <td style="padding: 0 0 8px 0; vertical-align: top; width: 20px; #{bullet_style_str};">
            <span style="color: #333333;">#{bullet}</span>
          </td>
          <td style="padding: 0 0 8px 0; #{content_style_str};">
            #{li.inner_html}
          </td>
        </tr>
      HTML
    end.join("\n")

    # Wrap the entire list in table structure
    table_html = <<~HTML
      <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%">
        <tr>
          <td style="padding: #{list_td_padding}; #{list_style};">
            <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%">
              #{rows_html}
            </table>
          </td>
        </tr>
      </table>
    HTML

    list.replace(table_html)
  end

  # Helper to determine button style selector based on classes
  def get_button_selector(classes, styles)
    return 'a.button' if classes.nil? || classes.empty?

    class_list = classes.split(/\s+/)
    has_secondary = class_list.include?('secondary') || class_list.include?('alt')
    has_tertiary = class_list.include?('tertiary') || class_list.include?('alt2')
    has_btn = class_list.include?('btn')

    if has_tertiary
      # Try tertiary selectors in order of preference
      ['a.button.tertiary', 'a.btn.alt2', 'a.button'].find { |sel| !styles.get_style(sel).empty? } || 'a.button'
    elsif has_secondary
      # Try secondary selectors in order of preference
      ['a.button.secondary', 'a.btn.alt', 'a.button'].find { |sel| !styles.get_style(sel).empty? } || 'a.button'
    elsif has_btn
      # Try btn selector, fallback to button
      ['a.btn', 'a.button'].find { |sel| !styles.get_style(sel).empty? } || 'a.button'
    else
      'a.button'
    end
  end

  # Convert links with .button or .btn class (and variants) to styled buttons
  button_selectors = ['a.button', 'a.btn', 'a.button.secondary', 'a.btn.alt', 'a.button.tertiary', 'a.btn.alt2']
  button_links = doc.css(button_selectors.join(', ')).reverse

  button_links.each do |a|
    href = a['href'] || '#'
    link_text = a.inner_text || a.text || ''

    # Escape HTML entities
    escaped_href = href.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
    escaped_text = link_text.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')

    # Determine which button style to use
    button_selector = get_button_selector(a['class'], styles)

    button_style = styles.style_string(button_selector)
    button_td_style = styles.get_style("#{button_selector} td")
    button_td_style['background'] || button_td_style['background-color'] || '#FF6B1A'
    button_td_style_str = styles.style_string("#{button_selector} td")
    wrapper_padding = styles.get_style('a.button-wrapper')['padding'] || '0 0 20px 0'
    fallback_style = styles.style_string('a.button-fallback')
    fallback_link_style = styles.style_string('a.button-fallback a')

    # Get span style for this button variant
    span_selector = "#{button_selector} span"
    span_style = styles.style_string(span_selector)

    button_html = <<~HTML
      <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%">
        <tr>
          <td align="center" style="padding: #{wrapper_padding};">
            <table role="presentation" cellspacing="0" cellpadding="0" border="0">
              <tr>
                <td align="center" style="#{button_td_style_str};">
                  <a href="#{escaped_href}" style="#{button_style};">
                    <span style="#{span_style};">
                      #{escaped_text}
                    </span>
                  </a>
                </td>
              </tr>
            </table>
          </td>
        </tr>
        <tr>
          <td align="center" style="#{fallback_style};">
            <p style="margin: 0; padding: 0;">Or paste this link into your browser: <a
                    href="#{escaped_href}" style="#{fallback_link_style};">
                    #{escaped_href}</a>
            </p>
          </td>
        </tr>
      </table>
    HTML

    a.replace(button_html)
  end

  # Style regular link elements (not buttons or button variants)
  doc.css('a:not(.button):not(.btn):not(.secondary):not(.tertiary):not(.alt):not(.alt2)').each do |a|
    existing_style = a['style'] || ''
    link_style = styles.style_string(link_selector)
    link_style = styles.style_string('a') if link_style.empty? && link_selector != 'a'
    a['style'] = "#{existing_style}; #{link_style}".gsub(/^; /, '').gsub(/;\s*;/, ';')
  end

  # Re-parse after table replacements
  html_string = doc.to_html
  doc = Nokogiri::HTML::DocumentFragment.parse(html_string)

  # Style images
  doc.css('img').reverse.each do |img|
    # Skip stack images - they're already in a table structure
    next if img['class']&.include?('stack-image')

    existing_style = img['style'] || ''
    base_img_style = styles.style_string('img')

    has_float_left = existing_style.include?('float: left') || existing_style.include?('float:left')
    has_float_right = existing_style.include?('float: right') || existing_style.include?('float:right')

    if has_float_left || has_float_right
      cleaned_style = existing_style
                      .gsub(/float\s*:\s*(left|right)\s*;?/i, '')
                      .gsub(/;\s*;/, ';')
                      .gsub(/^\s*;\s*/, '')
                      .gsub(/;\s*$/, '')

      float_direction = has_float_left ? 'left' : 'right'
      float_style = styles.style_string("img.float-#{float_direction}")
      img_style = "#{cleaned_style}; #{base_img_style}; #{float_style}".gsub(/^; /, '').gsub(/;\s*;/, ';')
      img['style'] = img_style

      margin_style = float_direction == 'left' ? 'margin: 0 1em 1em 0;' : 'margin: 0 0 1em 1em;'
      table_html = <<~HTML
        <table role="presentation" cellspacing="0" cellpadding="0" border="0" align="#{float_direction}" style="float: #{float_direction}; max-width: 100%; #{margin_style}">
          <tr>
            <td>
              #{img.to_html}
            </td>
          </tr>
        </table>
      HTML
      img.replace(table_html)
    else
      width = img['width']&.to_i || 0
      full_width_style = styles.style_string('img.full-width')

      if width >= 500 || img['width'].nil?
        img['style'] = "#{existing_style}; #{base_img_style}; #{full_width_style}".gsub(/^; /, '').gsub(/;\s*;/, ';')
        table_html = <<~HTML
          <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%">
            <tr>
              <td align="center" style="padding: 0;">
                #{img.to_html}
              </td>
            </tr>
          </table>
        HTML
        img.replace(table_html)
      else
        img['style'] = "#{existing_style}; #{base_img_style}; #{full_width_style}".gsub(/^; /, '').gsub(/;\s*;/, ';')
      end
    end
  end

  # Style strong/bold elements
  doc.css('strong, b').each do |strong|
    existing_style = strong['style'] || ''
    strong_style = styles.style_string('strong') || styles.style_string('b')
    strong['style'] = "#{existing_style}; #{strong_style}".gsub(/^; /, '').gsub(/;\s*;/, ';')
  end

  # Style emphasis/italic elements
  doc.css('em, i').each do |em|
    existing_style = em['style'] || ''
    em_style = styles.style_string('em') || styles.style_string('i')
    em['style'] = "#{existing_style}; #{em_style}".gsub(/^; /, '').gsub(/;\s*;/, ';')
  end

  doc.to_html
end

# Process liquid greeting tags in markdown content
# Returns: [processed_markdown, greeting_map]
# greeting_map: hash mapping placeholder indices to greeting text
def process_greeting_tags(markdown_content, default_greeting)
  greeting_map = {}
  processed_content = markdown_content.dup
  placeholder_index = 0

  # Find all {% greeting %} or {% salutation %} tags and replace with placeholders
  # Match: {% greeting %} or {% greeting "text" %} or {% greeting 'text' %}
  # Also match: {% salutation %} or {% salutation "text" %} or {% salutation 'text' %}
  processed_content.gsub!(/\{%\s*(?:greeting|salutation)\s*(?:"([^"]+)"|'([^']+)')?\s*%\}/) do
    # Extract the greeting text from the tag
    greeting_text = Regexp.last_match(1) || Regexp.last_match(2) || default_greeting
    placeholder = "{{GREETING_PLACEHOLDER_#{placeholder_index}}}"
    greeting_map[placeholder_index] = greeting_text
    placeholder_index += 1
    placeholder
  end

  [processed_content, greeting_map]
end

# Parse markdown reference definitions from content
# Returns: hash mapping reference names (lowercase) to URLs
# Format: [reference name]: URL
# Reference matching is case-insensitive
def parse_reference_definitions(markdown_content)
  references = {}
  # Match reference definitions: [name]: URL (with optional title)
  markdown_content.scan(/^\[([^\]]+)\]:\s+(\S+)(?:\s+["']([^"']+)["'])?\s*$/i) do |name, url, _title|
    # Store with lowercase key for case-insensitive lookup
    references[name.strip.downcase] = url.strip
  end
  references
end

# Process liquid button tags in markdown content
# Returns: processed_markdown with button tags replaced by markdown links
# Supports multiple syntaxes:
#   {% button class="primary" text="Click Here" url="https://example.com" %} - named attributes (class is optional)
#   {% button text="Click Here" url="https://example.com" %} - named attributes without class
#   {% button "Click Here" https://example.com %} - 2 args: text and url (default button)
#   {% button alt "Click Here" https://example.com %} - 3 args: class, text, url
#   {% button alt "Click Here" [reference] %} - 3 args with reference-style link
def process_button_tags(markdown_content, references = {})
  processed_content = markdown_content.dup

  # Pattern 1: {% button class="value" text="text" url="url" %} - named attributes (class is optional)
  # Also supports {% button class="value" text="text" url="[reference]" %} for reference-style links
  processed_content.gsub!(/\{%\s*button\s+(?:class\s*=\s*["']([^"']+)["']\s+)?text\s*=\s*["']([^"']+)["']\s+url\s*=\s*["']?\[?([^"'\]]+)\]?["']?\s*%\}/i) do
    class_name = Regexp.last_match(1) ? Regexp.last_match(1).strip : ''
    button_text = Regexp.last_match(2)
    button_url_param = Regexp.last_match(3).strip

    # Check if URL parameter is a reference (in square brackets or just the reference name)
    # Reference matching is case-insensitive
    button_url = if button_url_param =~ /^\[([^\]]+)\]$/
                   # Reference in square brackets: [reference]
                   ref_name = Regexp.last_match(1).strip.downcase
                   references[ref_name] || button_url_param
                 elsif references.key?(button_url_param.downcase)
                   # Just the reference name without brackets
                   references[button_url_param.downcase]
                 else
                   # Regular URL
                   button_url_param
                 end

    class_attr = class_name.empty? ? '' : " .#{class_name}"
    "[#{button_text}](#{button_url}){:.button#{class_attr}}"
  end

  # Pattern 2: {% button class "text" url %} - 3 positional args: class, text, url
  # Also supports {% button class "text" [reference] %} for reference-style links
  # Must process before pattern 3 (2 args) to avoid conflicts
  # Match 3 args: class name, quoted text, and URL or reference (where class is not a URL)
  # Reference can be in square brackets with spaces: [reference name]
  processed_content.gsub!(/\{%\s*button\s+(\S+)\s+["']([^"']+)["']\s+(\[[^\]]+\]|\S+)\s*%\}/) do |match|
    potential_class = Regexp.last_match(1).strip
    button_text = Regexp.last_match(2)
    button_url_param = Regexp.last_match(3).strip

    # Check if first arg looks like a URL (starts with http:// or https://)
    # If so, this is actually a 2-arg pattern, skip it
    next match if potential_class =~ %r{^https?://}

    # Check if URL parameter is a reference (in square brackets or just the reference name)
    # Reference matching is case-insensitive
    button_url = if button_url_param =~ /^\[([^\]]+)\]$/
                   # Reference in square brackets: [reference]
                   ref_name = Regexp.last_match(1).strip.downcase
                   references[ref_name] || button_url_param
                 elsif references.key?(button_url_param.downcase)
                   # Just the reference name without brackets
                   references[button_url_param.downcase]
                 else
                   # Regular URL
                   button_url_param
                 end

    class_name = potential_class.downcase
    # Map alt -> secondary, alt2 -> tertiary, primary -> empty (default), btn -> empty (default)
    mapped_class = case class_name
                   when 'alt2'
                     'tertiary'
                   when 'alt'
                     'secondary'
                   when 'primary', 'btn'
                     ''
                   else
                     class_name
                   end
    class_attr = mapped_class.empty? ? '' : " .#{mapped_class}"
    "[#{button_text}](#{button_url}){:.button#{class_attr}}"
  end

  # Pattern 3: {% button "text" url %} - 2 positional args: text and url (default button, no class)
  # Also supports {% button "text" [reference] %} for reference-style links
  # Must come after pattern 2 to avoid matching 3-arg patterns
  # Reference can be in square brackets with spaces: [reference name]
  processed_content.gsub!(/\{%\s*button\s+["']([^"']+)["']\s+(\[[^\]]+\]|\S+)\s*%\}/i) do
    button_text = Regexp.last_match(1)
    button_url_param = Regexp.last_match(2).strip

    # Check if URL parameter is a reference (in square brackets or just the reference name)
    # Reference matching is case-insensitive
    button_url = if button_url_param =~ /^\[([^\]]+)\]$/
                   # Reference in square brackets: [reference]
                   ref_name = Regexp.last_match(1).strip.downcase
                   references[ref_name] || button_url_param
                 elsif references.key?(button_url_param.downcase)
                   # Just the reference name without brackets
                   references[button_url_param.downcase]
                 else
                   # Regular URL
                   button_url_param
                 end

    "[#{button_text}](#{button_url}){:.button}"
  end

  processed_content
end

# Process liquid stack tags in markdown content
# Returns: [processed_markdown, stack_html_map]
# Supports two syntaxes:
#   {% stack %}
#   [![](/images/image1.png)](https://example.com/link1)
#   [![](/images/image2.png)](https://example.com/link2)
#   {% endstack %}
#
#   {% stack type="yaml" %}
#   images:
#     - path: /images/image1.png
#       url: https://example.com/link1
#     - path: /images/image2.png
#       url: https://example.com/link2
#   {% endstack %}
def process_stack_tags(markdown_content)
  processed_content = markdown_content.dup
  stack_map = {}
  placeholder_index = 0

  # Pattern to match {% stack %} ... {% endstack %} blocks
  # Handles optional attributes like type="yaml"
  processed_content.gsub!(/\{%\s*stack\s*(.*?)\s*%\}(.*?)\{%\s*endstack\s*%\}/m) do
    attributes = Regexp.last_match(1).strip
    content = Regexp.last_match(2).strip

    # Check if type="yaml" or type='yaml' is specified
    is_yaml = attributes =~ /type\s*=\s*["']yaml["']/i

    images = []
    if is_yaml
      # Parse YAML content
      begin
        yaml_data = YAML.safe_load(content)
        if yaml_data && yaml_data['images']
          yaml_data['images'].each do |img|
            path = img['path'] || img[:path]
            url = img['url'] || img[:url]
            images << { path: path, url: url }
          end
        end
      rescue StandardError => e
        warn "Warning: Could not parse YAML in stack tag: #{e.message}"
      end
    else
      # Parse markdown image links: [![](path)](url)
      # Also handle images without links: ![](path)
      # Pattern matches: [![](img_path)](link_url) or ![](img_path)
      content.scan(/\[!\[([^\]]*)\]\(([^)]+)\)\]\(([^)]+)\)|!\[([^\]]*)\]\(([^)]+)\)/) do |alt1, img_path1, link_url, alt2, img_path2|
        if img_path1 && !img_path1.empty?
          # Matched [![](path)](url) format
          images << { path: img_path1, url: link_url }
        elsif img_path2 && !img_path2.empty?
          # Matched ![](path) format (no link)
          images << { path: img_path2, url: nil }
        end
      end
    end

    # Generate HTML for the stack using table structure for email compatibility
    # Each image is in its own table row with no spacing
    table_rows = images.map do |img|
      # Escape HTML entities in paths and URLs
      escaped_path = (img[:path] || '').gsub('&', '&amp;').gsub('"', '&quot;').gsub('<', '&lt;').gsub('>', '&gt;')
      escaped_url = if img[:url] && !img[:url].strip.empty?
                      img[:url].gsub('&', '&amp;').gsub('"', '&quot;').gsub('<', '&lt;').gsub('>', '&gt;')
                    else
                      nil
                    end

      img_tag = "<img src=\"#{escaped_path}\" alt=\"\" class=\"stack-image\" style=\"display: block; width: 100%; height: auto; border: 0; margin: 0; padding: 0; vertical-align: top;\" />"
      img_content = if escaped_url
                      "<a href=\"#{escaped_url}\" style=\"display: block; text-decoration: none; border: 0; margin: 0; padding: 0;\">#{img_tag}</a>"
                    else
                      img_tag
                    end

      "<tr><td style=\"padding: 0; margin: 0; line-height: 0; font-size: 0;\">#{img_content}</td></tr>"
    end

    html = "<table role=\"presentation\" class=\"image-stack\" cellspacing=\"0\" cellpadding=\"0\" border=\"0\" width=\"100%\" style=\"width: 100%; margin: 0; padding: 0; border-collapse: collapse; border-spacing: 0;\"><tbody>#{table_rows.join}</tbody></table>"

    placeholder = "{{STACK_PLACEHOLDER_#{placeholder_index}}}"
    stack_map[placeholder_index] = html
    placeholder_index += 1
    placeholder
  end

  [processed_content, stack_map]
end

# Convert Markdown to plain text
def markdown_to_plain_text(markdown_content)
  plain_text = markdown_content.dup
  # Convert <br> and <br/> tags to single newlines (no blank line)
  plain_text = plain_text.gsub(%r{<br\s*/?>}i, "\n")
  # Remove other HTML tags but preserve their text content
  plain_text = plain_text.gsub(/<[^>]+>/, '')
  plain_text = plain_text.gsub(/\{[^}]*\}/, '')
  plain_text = plain_text.gsub(/\[([^\]]+)\]\(([^)]+)\)/) do
    link_text = Regexp.last_match(1)
    url = Regexp.last_match(2)
    "#{link_text} (#{url})"
  end
  # Normalize whitespace: collapse 3+ newlines to 2, but preserve single newlines
  # This preserves <br> newlines while removing excessive blank lines
  plain_text = plain_text.gsub(/\r\n/, "\n") # Normalize line endings
  plain_text = plain_text.gsub(/\n{3,}/, "\n\n") # Collapse excessive newlines
  plain_text.strip
end

# Send test email directly via SMTP
def send_test_email(to_address, subject, html_content, plain_text_content, config)
  email_config = config['email'] || {}
  smtp_config = config['smtp'] || {}

  from_name = email_config['from_name'] || 'Test Sender'
  from_email = email_config['from_email']
  reply_to = email_config['reply_to'] || from_email

  unless from_email
    warn 'Error: email.from_email not configured in config.yml (required for --test-send)'
    return false
  end

  smtp_host = smtp_config['host'] || 'localhost'
  smtp_port = smtp_config['port'] || 25
  smtp_domain = smtp_config['domain'] || 'localhost'
  smtp_user = smtp_config['user']
  smtp_password = smtp_config['password']
  smtp_auth = smtp_config['auth'] || (smtp_user && smtp_password ? 'plain' : nil)
  smtp_starttls = smtp_config['starttls'] || false
  smtp_ssl = smtp_config['ssl'] || false

  # Create email message
  message = <<~MESSAGE
    From: #{from_name} <#{from_email}>
    To: #{to_address}
    Reply-To: #{reply_to}
    Subject: #{subject}
    MIME-Version: 1.0
    Content-Type: multipart/alternative; boundary="mdtosendy_boundary"

    --mdtosendy_boundary
    Content-Type: text/plain; charset=UTF-8
    Content-Transfer-Encoding: 7bit

    #{plain_text_content}

    --mdtosendy_boundary
    Content-Type: text/html; charset=UTF-8
    Content-Transfer-Encoding: 7bit

    #{html_content}

    --mdtosendy_boundary--
  MESSAGE

  begin
    smtp = Net::SMTP.new(smtp_host, smtp_port)
    smtp.enable_starttls if smtp_starttls
    smtp.enable_ssl if smtp_ssl

    if smtp_user && smtp_password
      auth_method = smtp_auth ? smtp_auth.to_sym : :plain
      smtp.start(smtp_domain, smtp_user, smtp_password, auth_method) do |smtp_session|
        smtp_session.send_message(message, from_email, to_address)
      end
    else
      smtp.start(smtp_domain) do |smtp_session|
        smtp_session.send_message(message, from_email, to_address)
      end
    end
    puts "Test email sent successfully to #{to_address}"
    true
  rescue StandardError => e
    warn "Error sending test email: #{e.message}"
    false
  end
end

# Validate configuration
def validate_config(config)
  errors = []
  warnings = []

  # Check required Sendy config (only if creating campaigns)
  sendy_config = config['sendy'] || {}
  if sendy_config['api_url'].nil? || sendy_config['api_url'].empty?
    warnings << 'sendy.api_url is not set (required for campaign creation)'
  end
  if sendy_config['api_key'].nil? || sendy_config['api_key'].empty?
    warnings << 'sendy.api_key is not set (required for campaign creation)'
  end
  if sendy_config['brand_id'].nil? || sendy_config['brand_id'].empty?
    warnings << 'sendy.brand_id is not set (required for campaign creation)'
  end
  if sendy_config['list_ids'].nil? || sendy_config['list_ids'].empty?
    warnings << 'sendy.list_ids is not set (required for campaign creation)'
  end

  # Check email config
  email_config = config['email'] || {}
  warnings << 'email.from_name is not set' if email_config['from_name'].nil? || email_config['from_name'].empty?
  warnings << 'email.from_email is not set' if email_config['from_email'].nil? || email_config['from_email'].empty?
  warnings << 'email.reply_to is not set' if email_config['reply_to'].nil? || email_config['reply_to'].empty?

  # Check template config
  template_config = config['template'] || {}
  if template_config['header_image_url'].nil? || template_config['header_image_url'].empty?
    warnings << 'template.header_image_url is not set'
  end

  # Check paths
  paths_config = config['paths'] || {}
  if paths_config['template_file'].nil? || paths_config['template_file'].empty?
    errors << 'paths.template_file is not set'
  end
  errors << 'paths.styles_file is not set' if paths_config['styles_file'].nil? || paths_config['styles_file'].empty?

  # Check Markdown processor
  markdown_config = config['markdown'] || {}
  processor = markdown_config['processor'] || 'apex'
  # Extract command name (first word) for validation
  command_name = processor.strip.split(/\s+/).first
  # Check if processor command exists
  _stdout, _stderr, status = Open3.capture3('sh', '-c', "command -v #{command_name}")
  unless status.success?
    errors << "Markdown processor command '#{command_name}' is not installed or not in PATH"
    errors << '  Install it or configure a different processor in markdown.processor'
    errors << "  Current configuration: '#{processor}'"
  end

  { errors: errors, warnings: warnings }
end

# Validate styles
def validate_styles(styles)
  errors = []
  warnings = []

  # Check for essential styles
  required_styles = %w[body h1 h2 h3 p a]
  required_styles.each do |selector|
    if styles.get_style(selector).empty?
      warnings << "CSS rule for '#{selector}' is missing (recommended for proper styling)"
    end
  end

  # Check for button styles if buttons are used
  # Check primary button (a.button or a.btn)
  if styles.get_style('a.button').empty? && styles.get_style('a.btn').empty?
    warnings << "CSS rule for 'a.button' or 'a.btn' is missing (required if using button links)"
  end
  # Check secondary button if used
  if styles.get_style('a.button.secondary').empty? && styles.get_style('a.btn.alt').empty?
    warnings << "CSS rule for 'a.button.secondary' or 'a.btn.alt' is missing (optional, for secondary buttons)"
  end
  # Check tertiary button if used
  if styles.get_style('a.button.tertiary').empty? && styles.get_style('a.btn.alt2').empty?
    warnings << "CSS rule for 'a.button.tertiary' or 'a.btn.alt2' is missing (optional, for tertiary buttons)"
  end

  { errors: errors, warnings: warnings }
end

# Validate files exist
def validate_files(config, template_name = 'default')
  errors = []

  # Check template file (in template directory)
  template_directory = template_dir(template_name)
  template_file = File.join(template_directory, config.dig('paths', 'template_file') || 'email-template.html')
  errors << "Template file not found: #{template_file}" unless File.exist?(template_file)

  # Check styles file (in template directory)
  styles_file = File.join(template_directory, config.dig('paths', 'styles_file') || 'styles.css')
  errors << "Styles file not found: #{styles_file}" unless File.exist?(styles_file)

  { errors: errors, warnings: [] }
end

# Run all validations
def run_validation(config, styles, template_name = 'default')
  puts "Validating configuration and styles...\n\n"

  all_errors = []
  all_warnings = []

  # Validate config
  config_result = validate_config(config)
  all_errors.concat(config_result[:errors])
  all_warnings.concat(config_result[:warnings])

  # Validate styles
  styles_result = validate_styles(styles)
  all_errors.concat(styles_result[:errors])
  all_warnings.concat(styles_result[:warnings])

  # Validate files
  files_result = validate_files(config, template_name)
  all_errors.concat(files_result[:errors])
  all_warnings.concat(files_result[:warnings])

  # Report results
  if all_errors.empty? && all_warnings.empty?
    puts "✓ Validation passed! All checks successful.\n\n"
    return true
  end

  unless all_errors.empty?
    puts "✗ Errors found:\n"
    all_errors.each { |error| puts "  - #{error}" }
    puts "\n"
  end

  unless all_warnings.empty?
    puts "⚠ Warnings:\n"
    all_warnings.each { |warning| puts "  - #{warning}" }
    puts "\n"
  end

  all_errors.empty?
end

# Extract padding-top value from style hash
def extract_padding_top(style_hash)
  return nil unless style_hash.is_a?(Hash)

  style_hash['padding-top'] || style_hash['padding']&.split&.first
end

# Deep merge two hashes, with the second hash taking precedence
def deep_merge(base, override)
  return override if base.nil?
  return base if override.nil?
  return override unless base.is_a?(Hash) && override.is_a?(Hash)

  result = base.dup
  override.each do |key, value|
    result[key] = if result[key].is_a?(Hash) && value.is_a?(Hash)
                    deep_merge(result[key], value)
                  else
                    value
                  end
  end
  result
end

# S3 and SSH CDN settings share key names (username, password, path).
# When a template switches upload type, drop inherited keys from the other type
# unless explicitly set in that template's cdn configuration.
CDN_S3_ONLY_KEYS = %w[username password region acl].freeze
CDN_SSH_ONLY_KEYS = %w[hostname port].freeze
# Shared keys that are usually re-specified per upload type (path layout differs)
CDN_TYPE_LAYOUT_KEYS = %w[subdirectory].freeze

def sanitize_merged_cdn_config(merged_cdn, explicit_cdn)
  return merged_cdn unless merged_cdn.is_a?(Hash) && !merged_cdn.empty?

  result = merged_cdn.dup
  explicit = explicit_cdn.is_a?(Hash) ? explicit_cdn : {}
  type = result['type'].to_s.downcase

  case type
  when 's3'
    CDN_SSH_ONLY_KEYS.each { |key| result.delete(key) unless explicit.key?(key) }
  when 'scp', 'sftp'
    CDN_S3_ONLY_KEYS.each { |key| result.delete(key) unless explicit.key?(key) }
    # SCP/SFTP templates usually encode directory in path/url; don't inherit S3 subdirectory
    CDN_TYPE_LAYOUT_KEYS.each { |key| result.delete(key) unless explicit.key?(key) }
  end

  result
end

# Map flat frontmatter keys to nested config structure
# This allows users to use flat keys like 'header_image_url' instead of 'template.header_image_url'
def map_flat_keys_to_config(frontmatter)
  return {} if frontmatter.nil? || !frontmatter.is_a?(Hash)

  mapped = {}
  template_keys = %w[
    header_image_url header_image_alt header_image_width header_image_height
    signature_image_url signature_image_alt signature_image_width signature_image_height
    signature_text primary_footer footer_text greeting salutation
  ]
  email_keys = %w[from_name from_email reply_to]
  markdown_keys = %w[processor]
  campaign_keys = %w[track_opens track_clicks default_timezone]

  frontmatter.each do |key, value|
    # Skip keys that are already nested or are special keys (title, status, publish_date)
    next if %w[title status publish_date].include?(key)
    next if frontmatter[key].is_a?(Hash)

    if template_keys.include?(key)
      mapped['template'] ||= {}
      mapped['template'][key] = value
    elsif email_keys.include?(key)
      mapped['email'] ||= {}
      mapped['email'][key] = value
    elsif markdown_keys.include?(key)
      mapped['markdown'] ||= {}
      mapped['markdown'][key] = value
    elsif campaign_keys.include?(key)
      mapped['campaign'] ||= {}
      mapped['campaign'][key] = value
    end
  end

  mapped
end

# Merge frontmatter YAML into config, with frontmatter taking precedence
def merge_frontmatter_config(base_config, frontmatter)
  return base_config if frontmatter.nil? || !frontmatter.is_a?(Hash)

  # Map flat keys to nested structure
  mapped_flat = map_flat_keys_to_config(frontmatter)

  # Define key arrays for checking
  template_keys = %w[
    header_image_url header_image_alt header_image_width header_image_height
    signature_image_url signature_image_alt signature_image_width signature_image_height
    signature_text primary_footer footer_text greeting salutation
  ]
  email_keys = %w[from_name from_email reply_to]
  markdown_keys = %w[processor]
  campaign_keys = %w[track_opens track_clicks default_timezone]

  # Merge nested keys from frontmatter (if any)
  nested_override = {}
  frontmatter.each do |key, value|
    # Skip special keys and already mapped flat keys
    next if %w[title status publish_date].include?(key)
    next if template_keys.include?(key) || email_keys.include?(key) ||
            markdown_keys.include?(key) || campaign_keys.include?(key)

    # If it's a hash, it's a nested structure
    nested_override[key] = value if value.is_a?(Hash)
  end

  # Combine mapped flat keys and nested overrides
  frontmatter_override = deep_merge(mapped_flat, nested_override)

  merged = deep_merge(base_config, frontmatter_override)
  if frontmatter_override['cdn'].is_a?(Hash)
    merged = merged.dup
    merged['cdn'] = sanitize_merged_cdn_config(merged['cdn'] || {}, frontmatter_override['cdn'])
  end
  merged
end

# Replace template variables
def replace_template_variables(template, config, styles, title, content, primary_footer_html = '', signature_html = '',
                               footer_html = '')
  # Get primary footer style settings
  primary_footer_style = styles.style_string('.primary-footer')
  primary_footer_padding = extract_padding_top(styles.get_style('.primary-footer')) || '20px'

  # Wrap primary footer in a styled container if it exists
  primary_footer_content = ''
  unless primary_footer_html.nil? || primary_footer_html.strip.empty?
    primary_footer_content = <<~HTML
      <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%">
        <tr>
          <td style="padding: #{primary_footer_padding}; text-align: center; #{primary_footer_style};">
            #{primary_footer_html}
          </td>
        </tr>
      </table>
    HTML
  end

  # Use processed signature HTML if provided, otherwise fall back to raw text
  signature_content = signature_html
  if signature_content.nil? || signature_content.strip.empty?
    signature_content = config.dig('template', 'signature_text') || '-Brett'
  end

  # Get footer style settings
  footer_style = styles.style_string('.footer')
  footer_text_style = styles.style_string('.footer p')

  # Wrap footer text in a styled container if it exists
  footer_content = ''
  footer_content = footer_html unless footer_html.nil? || footer_html.strip.empty?

  template_vars = {
    'TITLE' => title,
    'CONTENT' => content,
    'BODY_STYLE' => styles.style_string('body'),
    'WRAPPER_STYLE' => styles.style_string('.wrapper'),
    'CONTENT_WRAPPER_STYLE' => styles.style_string('.content-wrapper'),
    'FONT_FAMILY' => styles.get_style('body')['font-family'] ||
                     'Avenir, system-ui, -apple-system, BlinkMacSystemFont, sans-serif',
    'HEADER_IMAGE_URL' => config.dig('template', 'header_image_url') || '',
    'HEADER_IMAGE_ALT' => config.dig('template', 'header_image_alt') || 'Email Header',
    'HEADER_IMAGE_WIDTH' => (config.dig('template', 'header_image_width') || 600).to_s,
    'HEADER_IMAGE_HEIGHT' => (config.dig('template', 'header_image_height') || 185).to_s,
    'SIGNATURE_IMAGE_URL' => config.dig('template', 'signature_image_url') || '',
    'SIGNATURE_IMAGE_ALT' => config.dig('template', 'signature_image_alt') || 'Signature',
    'SIGNATURE_IMAGE_WIDTH' => (config.dig('template', 'signature_image_width') || 98).to_s,
    'SIGNATURE_IMAGE_HEIGHT' => (config.dig('template', 'signature_image_height') || 98).to_s,
    'SIGNATURE_TEXT' => signature_content,
    'SIGNATURE_STYLE' => styles.style_string('.signature') || styles.style_string('p'),
    'SIGNATURE_TABLE_PADDING' => extract_padding_top(styles.get_style('.signature')) || '20px',
    'PRIMARY_FOOTER' => primary_footer_content,
    'FOOTER_STYLE' => footer_style,
    'FOOTER_TEXT_STYLE' => footer_text_style,
    'FOOTER_TEXT' => footer_content
  }

  result = template.dup
  template_vars.each do |key, value|
    result.gsub!("{{#{key}}}", value.to_s)
  end

  result
end

# Find CSS file path for dev file with parent fallback
def find_dev_css_path(template_name)
  # Check child template first
  child_css = File.join(template_dir(template_name), 'styles.css')
  return "templates/#{template_name}/styles.css" if File.exist?(child_css)

  # Check if template has a parent
  template_config_file = File.join(template_dir(template_name), 'config.yml')
  if File.exist?(template_config_file)
    begin
      template_config = YAML.safe_load(File.read(template_config_file)) || {}
      if template_config['parent']
        parent_name = template_config['parent']
        parent_css = File.join(template_dir(parent_name), 'styles.css')
        return "templates/#{parent_name}/styles.css" if File.exist?(parent_css)
      end
    rescue StandardError
      # Ignore errors
    end
  end

  # Default to default template
  'templates/default/styles.css'
end

# Generate email-dev.html for template development
def generate_dev_file(template_name)
  config = load_config(template_name)

  # Find CSS path (relative for link tag)
  css_path = find_dev_css_path(template_name)

  # Get full paths and replace home directory with ~
  home_dir = Dir.home
  template_path = template_dir(template_name)
  template_path_display = template_path.sub(home_dir, '~')

  # Find actual CSS file path (full path)
  css_file_path = File.join(config_dir, css_path)
  css_path_display = css_file_path.sub(home_dir, '~')

  # Load the actual email template
  template_filename = config.dig('paths', 'template_file') || 'email-template.html'
  template_file = find_template_file(template_name, template_filename)

  unless template_file && File.exist?(template_file)
    warn "Error: Template file not found: #{template_filename}"
    warn "Please ensure #{template_filename} exists in #{template_dir(template_name)}"
    exit 1
  end

  template = File.read(template_file)

  # Create sample markdown content
  sample_markdown = <<~MARKDOWN
    # Main Heading (H1)

    This is a paragraph of text. It demonstrates the paragraph styling with proper line height and spacing. You can edit the CSS file and see changes reflected immediately in your browser.

    ## Secondary Heading (H2)

    Another paragraph with some **bold text** and *italic text* to show text formatting styles.

    ### Tertiary Heading (H3)

    Here's a paragraph with a [regular link](https://example.com) to demonstrate link styling.

    [Click This Button](https://example.com){:.button}

    [Secondary Button](https://example.com){:.button .secondary}

    [Tertiary Button](https://example.com){:.button .tertiary}

    - First unordered list item
    - Second list item with **bold text**
    - Third list item with a [link](https://example.com)
    - Fourth list item

    1. First ordered list item
    2. Second ordered item
    3. Third ordered item

    Here's a full-width image:

    ![Placeholder](https://via.placeholder.com/600x300)

    Here's a floated image on the left:

    ![Placeholder](https://via.placeholder.com/200x200)

    This paragraph wraps around the floated image. You can see how the image floats to the left and text flows around it. This is useful for creating more interesting layouts in your emails.

    This paragraph clears the float.
  MARKDOWN

  # Convert markdown to HTML (but don't apply email styles - let CSS handle it)
  processor = config.dig('markdown', 'processor') || 'apex'
  html_content = markdown_to_html(sample_markdown, processor)

  # Post-process HTML to ensure button class is added to button links
  # Some markdown processors may not preserve the class attribute
  html_doc = Nokogiri::HTML::DocumentFragment.parse(html_content)
  html_doc.css('a').each do |link|
    link_text = link.text || ''
    existing_class = link['class'] || ''
    # Only add button class if it's missing (markdown processor may have already added classes)
    # Don't try to infer secondary/tertiary from text - let markdown classes handle that
    if !existing_class.include?('button') && !existing_class.include?('btn') && (link_text.include?('Click This Button') || link_text.include?('Secondary Button') || link_text.include?('Tertiary Button'))
      link['class'] = "#{existing_class} button".strip
    end
  end
  html_content = html_doc.to_html

  # Get template settings
  header_image_url = config.dig('template', 'header_image_url') || ''
  header_image_alt = config.dig('template', 'header_image_alt') || 'Email Header'
  header_image_width = (config.dig('template', 'header_image_width') || 600).to_s
  header_image_height = (config.dig('template', 'header_image_height') || 185).to_s
  signature_image_url = config.dig('template', 'signature_image_url') || ''
  signature_image_alt = config.dig('template', 'signature_image_alt') || 'Signature'
  signature_image_width = (config.dig('template', 'signature_image_width') || 98).to_s
  signature_image_height = (config.dig('template', 'signature_image_height') || 98).to_s
  # Get markdown processor
  processor = config.dig('markdown', 'processor') || 'apex'

  # Process signature text through markdown processor
  signature_text_raw = config.dig('template', 'signature_text') || '-Brett'
  signature_text_html = if signature_text_raw.strip.empty?
                          '-Brett'
                        elsif signature_text_raw.strip =~ /^<[a-z]/i && signature_text_raw.strip =~ %r{</[a-z]>.*$}i
                          # It's HTML, use as-is
                          signature_text_raw
                        else
                          # It's Markdown, convert to HTML
                          markdown_to_html(signature_text_raw, processor)
                        end

  # Process footer text through markdown processor
  footer_text_raw = config.dig('template', 'footer_text') || ''
  footer_text = if footer_text_raw.strip.empty?
                  "Copyright © #{Time.now.year} Your Name<br>123 Main St<br>City, State ZIP<br><br><webversion>View on the web</webversion> | <unsubscribe>Unsubscribe</unsubscribe>"
                elsif footer_text_raw.strip =~ /^<[a-z]/i && footer_text_raw.strip =~ %r{</[a-z]>.*$}i
                  # It's HTML, use as-is (but preserve webversion/unsubscribe tags)
                  footer_text_raw
                else
                  # It's Markdown, convert to HTML
                  # Extract webversion and unsubscribe tags first
                  webversion_content = ''
                  unsubscribe_content = ''
                  footer_without_tags = footer_text_raw.dup

                  if footer_without_tags =~ %r{<webversion>(.*?)</webversion>}i
                    webversion_content = Regexp.last_match(1)
                    footer_without_tags = footer_without_tags.gsub(%r{<webversion>.*?</webversion>}i,
                                                                   '___WEBVERSION___')
                  end

                  if footer_without_tags =~ %r{<unsubscribe>(.*?)</unsubscribe>}i
                    unsubscribe_content = Regexp.last_match(1)
                    footer_without_tags = footer_without_tags.gsub(%r{<unsubscribe>.*?</unsubscribe>}i,
                                                                   '___UNSUBSCRIBE___')
                  end

                  footer_html = markdown_to_html(footer_without_tags, processor)
                  # Restore webversion and unsubscribe tags
                  if webversion_content
                    footer_html = footer_html.gsub('___WEBVERSION___',
                                                   "<webversion>#{webversion_content}</webversion>")
                  end
                  if unsubscribe_content
                    footer_html = footer_html.gsub('___UNSUBSCRIBE___',
                                                   "<unsubscribe>#{unsubscribe_content}</unsubscribe>")
                  end
                  footer_html
                end

  # Create template info table HTML
  template_info_html = <<~HTML
    <!-- Template Info Table -->
    <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%" style="margin-bottom: 20px; background-color: #e8e8e8; border: 1px solid #d0d0d0;">
        <tr>
            <td style="padding: 15px 20px;">
                <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%">
                    <tr>
                        <td style="padding: 5px 10px 5px 0; font-family: menlo, courier, monospace; font-size: 12px; color: #000000; font-weight: bold;">
                            template:
                        </td>
                        <td style="padding: 5px 0; font-family: menlo, courier, monospace; font-size: 12px; color: #000000;">
                            #{template_name}
                        </td>
                    </tr>
                    <tr>
                        <td style="padding: 5px 10px 5px 0; font-family: menlo, courier, monospace; font-size: 12px; color: #000000; font-weight: bold;">
                            template path:
                        </td>
                        <td style="padding: 5px 0; font-family: menlo, courier, monospace; font-size: 12px; color: #000000;">
                            #{template_path_display}
                        </td>
                    </tr>
                    <tr>
                        <td style="padding: 5px 10px 5px 0; font-family: menlo, courier, monospace; font-size: 12px; color: #000000; font-weight: bold;">
                            style:
                        </td>
                        <td style="padding: 5px 0; font-family: menlo, courier, monospace; font-size: 12px; color: #000000;">
                            #{css_path_display}
                        </td>
                    </tr>
                </table>
            </td>
        </tr>
    </table>
  HTML

  # Add template info to content
  html_content = template_info_html + html_content

  # Replace template variables - but use empty strings for inline style placeholders
  # so CSS can take over
  template_vars = {
    'TITLE' => 'Email Template Development Preview',
    'CONTENT' => html_content,
    'BODY_STYLE' => '', # Let CSS handle it
    'WRAPPER_STYLE' => '', # Let CSS handle it
    'CONTENT_WRAPPER_STYLE' => '', # Let CSS handle it
    'FONT_FAMILY' => '', # Let CSS handle it
    'HEADER_IMAGE_URL' => header_image_url,
    'HEADER_IMAGE_ALT' => header_image_alt,
    'HEADER_IMAGE_WIDTH' => header_image_width,
    'HEADER_IMAGE_HEIGHT' => header_image_height,
    'SIGNATURE_IMAGE_URL' => signature_image_url,
    'SIGNATURE_IMAGE_ALT' => signature_image_alt,
    'SIGNATURE_IMAGE_WIDTH' => signature_image_width,
    'SIGNATURE_IMAGE_HEIGHT' => signature_image_height,
    'SIGNATURE_TEXT' => signature_text_html,
    'SIGNATURE_STYLE' => '', # Let CSS handle it
    'SIGNATURE_TABLE_PADDING' => '20px',
    'PRIMARY_FOOTER' => '',
    'FOOTER_STYLE' => '', # Let CSS handle it
    'FOOTER_TEXT_STYLE' => '', # Let CSS handle it
    'FOOTER_TEXT' => footer_text
  }

  dev_html = template.dup
  template_vars.each do |key, value|
    dev_html.gsub!("{{#{key}}}", value.to_s)
  end

  # Parse as full document first to add CSS link to head and add classes for CSS styling
  doc_full = Nokogiri::HTML::Document.parse(dev_html)
  head = doc_full.at_css('head')
  if head && !head.at_css('link[rel="stylesheet"]')
    link = Nokogiri::XML::Node.new('link', doc_full)
    link['rel'] = 'stylesheet'
    link['href'] = css_path
    head.add_child(link)
  end

  # Add wrapper class to outer wrapper table
  wrapper_table = doc_full.at_css('table[role="presentation"][width="100%"]')
  wrapper_table['class'] = 'wrapper' if wrapper_table && !wrapper_table['class']

  # Add content-wrapper class to main content table (width="600")
  content_table = doc_full.at_css('table[role="presentation"][width="600"]')
  content_table['class'] = 'content-wrapper' if content_table && !content_table['class']

  dev_html = doc_full.to_html

  # Replace signature div with paragraph for dev file (so it can be styled with CSS)
  # After template variable replacement, the signature div will have style="" and contain the signature text
  # Use Nokogiri to reliably find and replace
  # Parse as fragment for body content manipulation
  body_content = doc_full.at_css('body')&.inner_html || dev_html
  doc = Nokogiri::HTML::DocumentFragment.parse(body_content)

  # Find signature div (it's in a td that's next to the signature image)
  # Look for a div with empty style that's in a td containing a table with signature image
  signature_divs = doc.css('td div[style=""]')
  signature_div = signature_divs.find do |div|
    div.text.strip.length.positive? && !div.text.include?('Copyright') && !div.text.include?('webversion')
  end

  if signature_div
    signature_p = Nokogiri::XML::Node.new('p', doc)
    signature_p['class'] = 'signature'
    signature_p.inner_html = signature_div.inner_html
    signature_div.replace(signature_p)
  end

  # Find footer div and replace with paragraph, then add footer class to outermost td
  # The footer structure is: tr > td (with {{FOOTER_STYLE}}) > table > tr > td > div (with {{FOOTER_TEXT}})
  footer_div = doc.css('div').find do |div|
    div_text = div.text
    (div_text&.include?('Copyright') || div_text&.include?('webversion') || div_text&.include?('Unsubscribe')) && div['style'] == ''
  end
  if footer_div
    # Store the inner HTML and parent before replacement
    footer_html = footer_div.inner_html
    # Find the parent td that will contain the footer class (the one with {{FOOTER_STYLE}})
    # Walk up: div > td > tr > table > td > tr (the footer tr with the td that should have class="footer")
    parent_td = footer_div.ancestors('td').find { |td| td.parent.name == 'tr' && td.at_css('table') }
    # Replace div with paragraph
    footer_p = Nokogiri::XML::Node.new('p', doc)
    footer_p.inner_html = footer_html
    footer_div.replace(footer_p)
    # Add footer class to the td that contains the footer table
    if parent_td
      parent_td['class'] = 'footer'
    else
      # Fallback: find the tr that contains the footer table and get its td
      footer_tr = footer_p.ancestors('tr').find { |tr| tr.at_css('td table') }
      footer_tr&.at_css('td')&.[]=('class', 'footer')
    end
  end

  # Update body content with modified signature/footer
  body = doc_full.at_css('body')
  if body
    body.inner_html = doc.to_html
    # Add body padding
    existing_style = body['style'] || ''
    body['style'] = "#{existing_style}; padding: 20px;".gsub(/^; /, '')
    # Ensure wrapper and content-wrapper classes are still present after body update
    wrapper_table = doc_full.at_css('table[role="presentation"][width="100%"]')
    if wrapper_table && !wrapper_table['class']&.include?('wrapper')
      wrapper_table['class'] = "#{wrapper_table['class']} wrapper".strip
    end
    content_table = doc_full.at_css('table[role="presentation"][width="600"]')
    if content_table && !content_table['class']&.include?('content-wrapper')
      content_table['class'] = "#{content_table['class']} content-wrapper".strip
    end
    dev_html = doc_full.to_html
  else
    # Fallback: use fragment HTML and add body padding
    dev_html = doc.to_html
    dev_html = dev_html.sub(/<body[^>]*>/, '<body style="padding: 20px;">')
  end
  dev_file = File.join(config_dir, 'email-dev.html')
  File.write(dev_file, dev_html)
  puts "Generated email-dev.html at #{dev_file}"
  puts "CSS linked from: #{css_path}"
end

# Preview HTML in browser
def preview_html(html_file)
  if File.exist?(html_file)
    puts "Opening preview in browser: #{html_file}"
    system('open', html_file)
  else
    warn "Error: HTML file not found: #{html_file}"
    exit 1
  end
end

# Parse command-line arguments
def parse_args
  args = ARGV.dup
  flags = {
    validate: false,
    preview: false,
    template: nil,
    create_template: nil,
    parent: nil,
    dev: false,
    test_send: nil
  }

  # Remove flags from args
  i = 0
  while i < args.length
    arg = args[i]
    case arg
    when '--validate', '-v'
      flags[:validate] = true
      args.delete_at(i)
    when '--preview', '-p'
      flags[:preview] = true
      args.delete_at(i)
    when '--dev'
      flags[:dev] = true
      args.delete_at(i)
    when '--template', '-t'
      if i + 1 < args.length
        flags[:template] = args[i + 1]
        args.delete_at(i + 1)
        args.delete_at(i)
      else
        warn 'Error: --template requires a template name'
        exit 1
      end
    when '--create-template', '-c'
      if i + 1 < args.length
        flags[:create_template] = args[i + 1]
        args.delete_at(i + 1)
        args.delete_at(i)
      else
        warn 'Error: --create-template requires a template name'
        exit 1
      end
    when '--parent'
      if i + 1 < args.length
        flags[:parent] = args[i + 1]
        args.delete_at(i + 1)
        args.delete_at(i)
      else
        warn 'Error: --parent requires a parent template name'
        exit 1
      end
    when '--test-send'
      if i + 1 < args.length
        flags[:test_send] = args[i + 1]
        args.delete_at(i + 1)
        args.delete_at(i)
      else
        warn 'Error: --test-send requires an email address'
        exit 1
      end
    when '--help', '-h'
      puts "Usage: #{$0} [OPTIONS] <markdown_file>"
      puts "\nOptions:"
      puts '  --validate, -v           Validate configuration and styles without processing'
      puts '  --preview, -p            Open generated HTML in browser after processing'
      puts '  --test-send EMAIL        Send test email directly to EMAIL address (bypasses Sendy)'
      puts '  --dev                    Generate email-dev.html for template development'
      puts '  --template NAME, -t      Use template NAME (default: default)'
      puts '  --create-template NAME, -c   Create a new template directory with default files'
      puts '  --parent NAME             Use with --create-template to create a child template'
      puts '  --help, -h                Show this help message'
      puts "\nExamples:"
      puts "  #{$0} email.md                           # Generate HTML and TXT files"
      puts "  #{$0} --validate                          # Validate configuration only"
      puts "  #{$0} --preview email.md                  # Generate and preview in browser"
      puts "  #{$0} --template brettterpstra.com email.md  # Use specific template"
      puts "  #{$0} --create-template mytemplate        # Create a new template"
      puts "  #{$0} --create-template child --parent base  # Create child template"
      puts "  #{$0} --dev --template brett                # Generate dev file for brett template"
      puts "  #{$0} -v -p email.md                      # Validate, generate, and preview"
      exit 0
    else
      i += 1
    end
  end

  { flags: flags, markdown_file: args.first }
end

# Main script
parsed = parse_args
flags = parsed[:flags]
markdown_file = parsed[:markdown_file]

# Migrate old template files for backwards compatibility
migrate_old_template_files

# Ensure default template exists
ensure_default_template_exists

# Handle --create-template flag
if flags[:create_template]
  create_template(flags[:create_template], flags[:parent])
  exit 0
end

# Handle --dev flag
if flags[:dev]
  generate_dev_file(flags[:template] || 'default')
  exit 0
end

# Pre-read markdown file and YAML frontmatter (for template selection and config overrides)
yaml_config = nil
markdown_raw = nil
markdown_content = nil

if markdown_file
  unless File.exist?(markdown_file)
    warn "Error: File not found: #{markdown_file}"
    exit 1
  end

  markdown_raw = File.read(markdown_file)
  markdown_content = markdown_raw

  if markdown_raw =~ /\A---\s*\n(.*?)\n---\s*\n(.*)\z/m
    yaml_content = Regexp.last_match(1)
    markdown_content = Regexp.last_match(2)
    begin
      yaml_config = YAML.safe_load(yaml_content)
    rescue StandardError => e
      warn "Warning: Could not parse YAML frontmatter: #{e.message}"
    end
  end
end

# Determine template name, allowing CLI to override frontmatter
template_from_frontmatter = yaml_config.is_a?(Hash) ? yaml_config['template'] : nil
template_name = if flags[:template]
                  flags[:template]
                elsif template_from_frontmatter && !template_from_frontmatter.to_s.strip.empty?
                  template_from_frontmatter.to_s
                else
                  'default'
                end

# Load configuration and styles
config = load_config(template_name)
styles = load_styles(template_name)

# Run validation if requested
if flags[:validate] && markdown_file.nil?
  success = run_validation(config, styles, template_name)
  exit(success ? 0 : 1)
end

# If markdown file is provided, process it
if markdown_file
  # Run validation if requested (but continue processing)
  if flags[:validate]
    success = run_validation(config, styles, template_name)
    puts "\nContinuing with processing despite validation issues...\n\n" unless success
  end

  # Derive output filenames
  base_name = File.basename(markdown_file, File.extname(markdown_file))
  output_dir = File.dirname(markdown_file)
  html_file = File.join(output_dir, "#{base_name}.html")
  txt_file = File.join(output_dir, "#{base_name}.txt")

  # Read template from template directory (with parent fallback)
  template_filename = config.dig('paths', 'template_file') || 'email-template.html'
  template_file = find_template_file(template_name, template_filename)

  unless template_file && File.exist?(template_file)
    warn "Error: Template file not found: #{template_filename}"
    warn "Please ensure #{template_filename} exists in #{template_dir(template_name)}"
    if template_name == 'default'
      warn "Or create a new template with: #{$0} --create-template default"
    else
      warn "Or create a new template with: #{$0} --create-template #{template_name}"
    end
    exit 1
  end

  template = File.read(template_file)

  # Merge frontmatter into config (frontmatter takes precedence) if present
  config = merge_frontmatter_config(config, yaml_config) if yaml_config

  # Get default greeting from config (can be overridden by frontmatter)
  # Support both 'greeting' and 'salutation' keys, with 'salutation' taking precedence if both exist
  template_config = config.dig('template') || {}
  has_greeting = template_config.key?('greeting') && !template_config['greeting'].nil? && !template_config['greeting'].to_s.strip.empty?
  has_salutation = template_config.key?('salutation') && !template_config['salutation'].nil? && !template_config['salutation'].to_s.strip.empty?

  if has_greeting && has_salutation
    warn "Warning: Both 'greeting' and 'salutation' are defined in config. Using 'salutation'."
    default_greeting = template_config['salutation'].to_s
  elsif has_salutation
    default_greeting = template_config['salutation'].to_s
  elsif has_greeting
    default_greeting = template_config['greeting'].to_s
  else
    default_greeting = ''
  end

  # Parse markdown reference definitions before processing tags
  references = parse_reference_definitions(markdown_content)

  # Process greeting tags in markdown
  processed_markdown, greeting_map = process_greeting_tags(markdown_content, default_greeting)

  # Process button tags in markdown (convert to markdown link syntax)
  processed_markdown = process_button_tags(processed_markdown, references)

  # Process stack tags in markdown (convert to placeholders)
  processed_markdown, stack_map = process_stack_tags(processed_markdown)

  # Convert Markdown to HTML
  processor = config.dig('markdown', 'processor') || 'apex'
  html_content = markdown_to_html(processed_markdown, processor)

  # Process greeting placeholders - convert greeting text to HTML (but don't apply styles yet)
  # We'll apply styles after all HTML is processed
  greeting_html_map = {}
  greeting_map.each do |index, greeting_text|
    # Process greeting text as markdown/HTML
    greeting_html_map[index] = if greeting_text.strip =~ /^<[a-z]/i && greeting_text.strip =~ %r{</[a-z]>.*$}i
                                 # It's HTML, store as-is (will apply styles later)
                                 greeting_text
                               else
                                 # It's Markdown, convert to HTML
                                 markdown_to_html(greeting_text, processor)
                               end
    # Replace placeholder with processed HTML (before styles are applied)
    html_content = html_content.gsub("{{GREETING_PLACEHOLDER_#{index}}}", greeting_html_map[index])
  end

  # Process stack placeholders - replace with HTML (before CDN upload so images can be uploaded)
  stack_map.each do |index, stack_html|
    html_content = html_content.gsub("{{STACK_PLACEHOLDER_#{index}}}", stack_html)
  end

  # Upload local images to CDN if configured (after stack placeholders are replaced)
  cdn_config = config['cdn']
  if cdn_config && cdn_config['url'] && cdn_config['type']
    markdown_file_dir = File.dirname(File.expand_path(markdown_file))
    html_content = upload_and_replace_images(html_content, cdn_config, markdown_file_dir)
  end

  # Determine if we should insert default greeting
  # Only insert if no greeting tags were found in markdown and default greeting is set
  has_greeting_tags = !greeting_map.empty?
  should_insert_default_greeting = !has_greeting_tags && !default_greeting.nil? && !default_greeting.strip.empty?

  # Process default greeting if needed (before applying styles)
  if should_insert_default_greeting
    # Process greeting as markdown/HTML
    greeting_raw = default_greeting
    default_greeting_html = if greeting_raw.strip =~ /^<[a-z]/i && greeting_raw.strip =~ %r{</[a-z]>.*$}i
                              # It's HTML, use as-is
                              greeting_raw
                            else
                              # It's Markdown, convert to HTML
                              markdown_to_html(greeting_raw, processor)
                            end

    # Insert greeting after header, before first paragraph
    # Greeting will be treated as a paragraph with proper spacing from table layout

    # Find the first paragraph or heading and insert greeting before it
    doc = Nokogiri::HTML::DocumentFragment.parse(html_content)
    first_element = doc.at_css('p, h1, h2, h3, ul, ol, blockquote')
    if first_element
      # Insert greeting before the first element
      greeting_fragment = Nokogiri::HTML::DocumentFragment.parse(default_greeting_html)
      first_element.add_previous_sibling(greeting_fragment)
      html_content = doc.to_html
    else
      # No paragraphs found, prepend to content
      html_content = "#{default_greeting_html}#{html_content}"
    end
  end

  # Apply email styles (this will style both content and any inserted greetings)
  styled_html = apply_email_styles(html_content, styles)

  # Extract title
  title = 'Email'
  if yaml_config && yaml_config['title']
    title = yaml_config['title']
  elsif styled_html =~ %r{<h1[^>]*>(.*?)</h1>}i
    title = Regexp.last_match(1).strip
  end

  # Process primary footer if configured
  primary_footer_html = ''
  primary_footer_raw = config.dig('template', 'primary_footer')
  if primary_footer_raw && !primary_footer_raw.strip.empty?
    # Check if it looks like HTML or Markdown
    # If it starts with < and contains HTML tags, treat as HTML
    # Otherwise, treat as Markdown
    if primary_footer_raw.strip =~ /^<[a-z]/i && primary_footer_raw.strip =~ %r{</[a-z]>.*$}i
      # It's HTML, just apply styles
      primary_footer_html = apply_email_styles(primary_footer_raw, styles)
    else
      # It"s Markdown, convert to HTML then apply styles"
      primary_footer_markdown_html = markdown_to_html(primary_footer_raw, processor)
      primary_footer_html = apply_email_styles(primary_footer_markdown_html, styles)
    end
  end

  # Process signature text if configured
  signature_html = ''
  signature_raw = config.dig('template', 'signature_text') || '-Brett'
  if signature_raw && !signature_raw.strip.empty?
    # Check if it looks like HTML or Markdown
    # If it starts with < and contains HTML tags, treat as HTML
    # Otherwise, treat as Markdown
    if signature_raw.strip =~ /^<[a-z]/i && signature_raw.strip =~ %r{</[a-z]>.*$}i
      # It's HTML, just apply styles
      signature_html = apply_email_styles(signature_raw, styles)
    else
      # It's Markdown, convert to HTML then apply styles
      signature_markdown_html = markdown_to_html(signature_raw, processor)
      signature_html = apply_email_styles(signature_markdown_html, styles)
    end
  end

  # Process footer text if configured
  footer_html = ''
  footer_raw = config.dig('template', 'footer_text')
  if footer_raw && !footer_raw.strip.empty?
    # Extract webversion and unsubscribe content before processing
    webversion_content = ''
    unsubscribe_content = ''

    footer_without_tags = footer_raw.dup

    # Extract and replace webversion tag with an HTML span placeholder
    if footer_without_tags =~ %r{<webversion>(.*?)</webversion>}i
      webversion_content = Regexp.last_match(1)
      placeholder = '<span data-mdtosendy="webversion"></span>'
      footer_without_tags = footer_without_tags.gsub(%r{<webversion>.*?</webversion>}i, placeholder)
    end

    # Extract and replace unsubscribe tag with an HTML span placeholder
    if footer_without_tags =~ %r{<unsubscribe>(.*?)</unsubscribe>}i
      unsubscribe_content = Regexp.last_match(1)
      placeholder = '<span data-mdtosendy="unsubscribe"></span>'
      footer_without_tags = footer_without_tags.gsub(%r{<unsubscribe>.*?</unsubscribe>}i, placeholder)
    end

    # Check if it looks like HTML or Markdown
    # If it starts with < and contains HTML tags, treat as HTML
    # Otherwise, treat as Markdown
    if footer_without_tags.strip =~ /^<[a-z]/i && footer_without_tags.strip =~ %r{</[a-z]>.*$}i
      # It's HTML, just apply styles
      footer_html = apply_email_styles(footer_without_tags, styles, link_selector: '.footer a')
    else
      # It's Markdown, convert to HTML then apply styles
      footer_markdown_html = markdown_to_html(footer_without_tags, processor)
      footer_html = apply_email_styles(footer_markdown_html, styles, link_selector: '.footer a')
    end

    # Restore webversion and unsubscribe as styled anchor tags (Sendy replaces [webversion]/[unsubscribe] in href)
    if footer_html.include?('data-mdtosendy')
      footer_link_style = styles.style_string('.footer a')
      footer_link_style = styles.style_string('a') if footer_link_style.empty?
      style_attr = footer_link_style.empty? ? '' : " style=\"#{footer_link_style}\""
      doc = Nokogiri::HTML::DocumentFragment.parse(footer_html)
      doc.css('span[data-mdtosendy="webversion"]').each do |span|
        span.replace("<a href=\"[webversion]\"#{style_attr}>#{webversion_content}</a>")
      end
      doc.css('span[data-mdtosendy="unsubscribe"]').each do |span|
        span.replace("<a href=\"[unsubscribe]\"#{style_attr}>#{unsubscribe_content}</a>")
      end
      footer_html = doc.to_html
    end
  end

  # Replace template variables
  final_html = replace_template_variables(
    template, config, styles, title, styled_html, primary_footer_html, signature_html, footer_html
  )

  # Write HTML file
  File.write(html_file, final_html)
  puts "HTML email generated: #{html_file}"

  # Generate plain text version
  plain_text_content = markdown_to_plain_text(markdown_content)
  signature_text_raw = config.dig('template', 'signature_text') || '-Brett'

  # Process signature text for plain text (convert Markdown to plain text)
  signature_text = signature_text_raw
  if signature_text_raw && !signature_text_raw.strip.empty?
    # If it's HTML, extract text content; otherwise treat as Markdown
    if signature_text_raw.strip =~ /^<[a-z]/i && signature_text_raw.strip =~ %r{</[a-z]>.*$}i
      # It's HTML, extract plain text
      doc = Nokogiri::HTML::DocumentFragment.parse(signature_text_raw)
      signature_text = doc.text.strip
    else
      # It"s Markdown, convert to plain text"
      signature_text = markdown_to_plain_text(signature_text_raw)
    end
  end

  # Add primary footer to plain text if configured
  primary_footer_text = ''
  if primary_footer_raw && !primary_footer_raw.strip.empty?
    primary_footer_text = "\n\n#{markdown_to_plain_text(primary_footer_raw)}\n"
  end

  # Add footer text to plain text if configured
  footer_text_plain = ''
  if footer_raw && !footer_raw.strip.empty?
    # Remove webversion and unsubscribe tags before converting to plain text
    # We'll add them back in the proper format at the end
    footer_for_plain = footer_raw.dup
    has_webversion = false
    has_unsubscribe = false

    # Check for and remove webversion tag
    if footer_for_plain =~ %r{<webversion>.*?</webversion>}i
      has_webversion = true
      footer_for_plain = footer_for_plain.gsub(%r{<webversion>.*?</webversion>}i, '')
    end

    # Check for and remove unsubscribe tag
    if footer_for_plain =~ %r{<unsubscribe>.*?</unsubscribe>}i
      has_unsubscribe = true
      footer_for_plain = footer_for_plain.gsub(%r{<unsubscribe>.*?</unsubscribe>}i, '')
    end

    # Convert <br> and <br/> tags to a placeholder, then process, then convert to single newline
    # This ensures <br> becomes exactly one newline, not two (even if followed by a newline in YAML)
    footer_for_plain = footer_for_plain.gsub(%r{<br\s*/?>}i, '___BR_PLACEHOLDER___')

    # Clean up any separators (like "|") that were between the tags
    footer_for_plain = footer_for_plain.gsub(/\s*\|\s*/, "\n")

    # Convert remaining footer content to plain text
    footer_text_plain = markdown_to_plain_text(footer_for_plain).strip

    # Replace <br> placeholder with single newline, ensuring no double newlines
    # Replace placeholder that might be followed by a newline with just one newline
    footer_text_plain = footer_text_plain
                        .gsub(/___BR_PLACEHOLDER___\n?/, "\n")
                        .gsub(/\n{3,}/, "\n\n") # Collapse excessive newlines
                        .strip

    # Add webversion and unsubscribe in proper format
    footer_lines = []
    footer_lines << footer_text_plain unless footer_text_plain.empty?
    footer_lines << 'Web Version: [webversion]' if has_webversion
    footer_lines << 'Unsubscribe: [unsubscribe]' if has_unsubscribe

    footer_text_plain = footer_lines.join("\n")
    footer_text_plain = "\n\n---\n\n#{footer_text_plain}\n" unless footer_text_plain.empty?
  else
    # Default footer if not configured
    footer_text_plain = "\n\n---\n\nWeb Version: [webversion]\n\nUnsubscribe: [unsubscribe]\n"
  end

  plain_text = <<~TEXT
    #{plain_text_content}

    #{signature_text}#{primary_footer_text}#{footer_text_plain}
  TEXT

  # Write TXT file
  File.write(txt_file, plain_text)
  puts "Plain text email generated: #{txt_file}"

  # Preview if requested
  if flags[:preview]
    preview_html(html_file)
    puts "\nPreview mode: Skipping Sendy campaign creation."
    exit 0
  end

  # Send test email if requested
  if flags[:test_send]
    subject = yaml_config && yaml_config['title'] ? yaml_config['title'] : 'Test Email'
    if send_test_email(flags[:test_send], subject, final_html, plain_text, config)
      puts "\nTest email mode: Skipping Sendy campaign creation."
      exit 0
    else
      exit 1
    end
  end
elsif ARGV.empty?
  # Show usage if no arguments provided
  puts "Usage: #{$0} [OPTIONS] <markdown_file>"
  puts "\nOptions:"
  puts '  --validate, -v           Validate configuration and styles without processing'
  puts '  --preview, -p            Open generated HTML in browser after processing'
  puts '  --template NAME, -t      Use template NAME (default: default)'
  puts '  --create-template NAME, -c   Create a new template directory with default files'
  puts '  --parent NAME             Use with --create-template to create a child template'
  puts '  --help, -h                Show this help message'
  puts "\nExamples:"
  puts "  #{$0} email.md                           # Generate HTML and TXT files"
  puts "  #{$0} --validate                          # Validate configuration only"
  puts "  #{$0} --preview email.md                  # Generate and preview in browser"
  puts "  #{$0} --test-send test@example.com email.md  # Send test email directly"
  puts "  #{$0} --template brettterpstra.com email.md  # Use specific template"
  puts "  #{$0} --create-template mytemplate        # Create a new template"
  puts "  #{$0} --create-template child --parent base  # Create child template"
  puts "  #{$0} -v -p email.md                      # Validate, generate, and preview"
  exit 0
else
  warn 'Error: Markdown file is required (unless using --validate only)'
  warn 'Use --help for usage information'
  exit 1
end

# Create Sendy campaign if YAML config has title (skip if preview mode or test-send mode)
unless flags[:preview] || flags[:test_send]
  if yaml_config && yaml_config['title']
    sendy_config = config['sendy'] || {}
    email_config = config['email'] || {}
    campaign_config = config['campaign'] || {}

    create_url = sendy_config['api_url']
    unless create_url
      warn 'Error: sendy.api_url not configured in config.yml'
      exit 1
    end

    uri = URI(create_url)

    is_draft = yaml_config['status'] == 'draft' || !yaml_config['publish_date']
    publish_date = nil

    params = {
      api_key: sendy_config['api_key'],
      brand_id: sendy_config['brand_id'],
      from_name: email_config['from_name'],
      from_email: email_config['from_email'],
      reply_to: email_config['reply_to'],
      title: yaml_config['title'],
      subject: yaml_config['title'],
      plain_text: plain_text,
      html_text: final_html,
      list_ids: sendy_config['list_ids'],
      track_opens: campaign_config['track_opens'] || '1',
      track_clicks: campaign_config['track_clicks'] || '1'
    }

    if is_draft
      params[:send_campaign] = '0'
    else
      begin
        publish_date = Time.parse(yaml_config['publish_date'])
      rescue StandardError => e
        warn "Warning: Could not parse publish_date: #{e.message}"
        puts 'No campaign created. Invalid publish_date format.'
        exit 0
      end
      params[:schedule_date_time] = publish_date.strftime('%B %d, %Y %I:%M%p')
      params[:schedule_timezone] = campaign_config['default_timezone'] || 'America/Chicago'
    end

    # Make HTTP request
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    request = Net::HTTP::Post.new(uri.path)
    request.set_form_data(params)

    res = http.request(request)
    if res.is_a?(Net::HTTPSuccess)
      puts res.body
      if is_draft
        puts 'Draft campaign created.'
      else
        puts "Campaign created and scheduled for #{publish_date.strftime('%Y-%m-%d %H:%M')}"
      end

      # Check for followup URL
      followup_url = sendy_config['followup_url']
      if followup_url && !followup_url.strip.empty?
        print 'Open the followup URL in your browser? (Y/n): '
        response = $stdin.gets.chomp.strip.downcase
        system('open', followup_url) if response.empty? || response == 'y'
      end
    else
      warn "Error creating campaign: #{res.code} #{res.message}"
      warn res.body if res.body
    end
  elsif yaml_config.nil? || !yaml_config['title']
    puts "\nNo campaign created. To create a campaign, add a YAML header with `title` (and optionally `publish_date` or `status: draft`) to the Markdown file."
  end
end
