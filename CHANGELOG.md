#### FIXED

- **Invalid YAML** in frontmatter, stack tags, or config files now stops processing with exit status 1 (line/column still reported)

#### NEW

- Multiple Markdown file arguments and globs; files are processed in order with shared flags

#### CHANGED

- Preview and test-send modes run for each file in a multi-file invocation instead of exiting after the first
- Invalid publish_date now exits with status 1 (was 0)

#### CHANGED

- **Webversion and unsubscribe tags** are output as styled anchor tags with [webversion]/[unsubscribe] hrefs for Sendy replacement
- **Overwrite prompt** wording updated to reflect that the existing CDN URL will be used when declining

#### NEW

- Specify template for an email in YAML front matter, can be overridden on command line

#### FIXED

- **SCP/SFTP CDN uploads** no longer inherit S3 username/password (or subdirectory) from base config when a template switches upload type, preventing bogus SSH password prompts
- **Declining CDN overwrite** now reuses the existing CDN URL instead of leaving a local file path in the output HTML
- **Floated images** no longer forced to max-width: 30%; they keep max-width: 100% from the base img rule
- **Footer links** now styled with .footer a selector, falling back to a when not defined

#### FIXED

- SCP/SFTP CDN templates no longer inherit S3 username/password from base config when switching upload type
- Floated images no longer force max-width: 30%; they keep max-width: 100% from the base img rule
- Declining CDN overwrite now reuses the existing CDN URL instead of leaving a local file path

#### CHANGED

- CDN configuration supports optional subdirectory, region, and ACL settings
- Test email sending sends both HTML and plain text versions as multipart/alternative message
- CDN uploads now use original filenames by default instead of adding timestamps
- Default overwrite behavior changed from false to ask (prompts when file exists)

#### NEW

- Added CDN image upload functionality supporting S3, SCP, and SFTP upload methods
- Added automatic detection and upload of local images in Markdown files with URL replacement in output HTML
- Added --test-send flag to send test emails directly via SMTP without creating Sendy campaigns
- Added SMTP configuration section with support for host, port, authentication, STARTTLS, and SSL
- Added Gemfile for easy dependency management with bundle install
- Added content-type detection for image uploads based on file extension
- Added cache-control headers to S3 uploads for better email client compatibility
- Added support for ed25519 SSH keys by including ed25519 and bcrypt_pbkdf gems in Gemfile
- Added {% stack %} liquid tag for creating vertical stacks of images with no spacing between them
- Stack tag supports markdown image syntax with optional links: [![](path)](url) or ![](path)
- Stack tag supports YAML syntax with type="yaml" attribute for structured image definitions
- Added CDN overwrite configuration option with three modes: true (always), false (never), ask/prompt (default)
- Added file existence checking for S3, SFTP, and SCP uploads before overwriting
- Added interactive prompt for overwrite confirmation with single-character input (no Enter required)

#### IMPROVED

- S3 uploads now set public-read ACL by default (with graceful handling for ACL-disabled buckets)
- Image path resolution now handles absolute paths, relative paths, and paths relative to markdown file directory
- SCP/SFTP uploads now support SSH key-based authentication using SSH config aliases (username and password optional)
- SCP/SFTP uploads now automatically expand ~ in remote paths to the user's home directory
- SCP/SFTP uploads now use system known_hosts file for host key verification
- SCP/SFTP error messages now include local file path and remote path for debugging
- Overwrite prompt now includes verbose description explaining timestamp behavior
- Overwrite prompt defaults to Yes (Y/n) instead of No (y/N)
- Stack images use table-based layout for maximum email client compatibility
- Stack images are excluded from standard image styling to prevent double-wrapping
- Stack images render with zero vertical spacing and full width of content area

#### FIXED

- S3 uploads now set correct content-type headers to prevent images from downloading instead of displaying
- Error handling for missing CDN upload gems with helpful installation messages
- SCP upload error handling now properly handles StringWithExitstatus objects and provides better error messages
- Host key mismatch errors now show correct fingerprint and host information
- Stack images now upload to CDN correctly by processing placeholders before CDN upload

### 1.0.7

2026-01-17 04:05

#### NEW

- Added --test-send EMAIL_ADDRESS flag to send test emails directly via SMTP without going through Sendy
- Added SMTP configuration section with support for host, port, authentication, STARTTLS, and SSL
- Test email sends both HTML and plain text versions as multipart/alternative message
- Test email mode skips Sendy campaign creation and exits after sending
- Added Gmail-specific SMTP configuration examples in config.example.yml

### 1.0.6

2026-01-17 04:00

#### CHANGED

- Updated config.example.yml to document salutation alias
- Updated README.md to document salutation as alias for greeting in all usage contexts
- Reference matching is case-insensitive for both reference definitions and button tag lookups
- Updated README.md to document button liquid tag syntaxes including reference-style links
- Updated README to note greeting spacing is handled by table layout
- Updated secondary button styling to match primary button appearance (border-radius, box-shadow, padding, font properties)
- Updated styles.example.css and all template styles.css files with consistent secondary button styling
- Define a greeting in template configs to be inserted at the beginning of the email automatically
- Use `{% greeting %}` to modify where the greeting is inserted
- Use `{% greeting "Hey there!" %}` in the Markdown to override both location and content
- Use `greeting: Hello!` in the Markdown file's YAML to override configured greeting
- Added salutation as alias for greeting in config (salutation takes precedence if both are defined)
- Added warning when both greeting and salutation are defined in config
- Added {% salutation %} as alias for {% greeting %} liquid tag
- Added {% button %} liquid tag to generate styled button links in markdown
- Support for {% button class="primary" text="Click Here" url="https://example.com" %} syntax with named attributes (class optional)
- Support for {% button "Click Here" https://example.com %} two-argument syntax (text and url, default button)
- Support for {% button alt "Click Here" https://example.com %} three-argument syntax (class, text, url)
- Automatic mapping of alt -> secondary, alt2 -> tertiary for button classes
- Button tags convert to markdown link syntax with button classes for processing by existing button styling system
- Added support for markdown reference-style links in button tags using square brackets
- Button tags can now use reference definitions like {% button alt "Text" [Reference Name] %}
- Added parse_reference_definitions function to extract reference definitions from markdown content
- Added followup_url config option in sendy section to automatically open a URL in browser after creating a campaign
- Added interactive prompt asking user to confirm opening followup URL (defaults to yes)
- Followup URL is ignored when using --preview flag since preview already opens in browser
- Fixed NameError in get_button_selector function by adding styles as a parameter instead of accessing it from closure scope
- Updated config files using Ruby instead of sed to work with Fish shell
- Removed line breaks from default greeting insertion (spacing now handled by table layout)
- Updated button tag regex patterns to support references with spaces in square brackets

#### NEW

- Added --test-send EMAIL_ADDRESS flag to send test emails directly via SMTP without going through Sendy
- Added SMTP configuration section with support for host, port, authentication, STARTTLS, and SSL
- Test email sends both HTML and plain text versions as multipart/alternative message
- Test email mode skips Sendy campaign creation and exits after sending
- Added Gmail-specific SMTP configuration examples in config.example.yml

### 1.0.5

2025-12-30 09:38

#### CHANGED

- Template files (HTML and CSS) are now loaded from template-specific directories instead of root config directory
- Config loading now merges base config with template-specific config, with template config taking precedence
- Template config files support parent key to create child templates that inherit and override parent settings
- CSS margin and padding on elements are now automatically converted to table cell padding during email generation
- Elements can now use margin/padding in CSS file and it will work in both dev preview and final email
- Updated styles.example.css and template CSS files to use margin on elements instead of setting margin/padding to 0
- Removed element td padding selectors from CSS files, replaced with margin on elements
- Template info table shows ~ instead of full home directory path
- Template info table shows full CSS file path (~/.config/mdtosendy/templates/...) instead of relative path
- Signature text in email-dev.html now uses <p class="signature"> instead of table-based div, allowing CSS styling
- Footer text in email-dev.html now uses <p> inside a <td class="footer">, allowing CSS styling with .footer and .footer p selectors
- Signature text in email-dev.html is now processed through configured markdown processor instead of simple newline replacement
- Footer text in email-dev.html is now processed through configured markdown processor instead of simple newline replacement
- Footer text processing preserves <webversion> and <unsubscribe> tags when converting markdown to HTML
- Updated button link detection to include all button class variants (.button, .btn, .secondary, .tertiary, .alt, .alt2)
- Updated validation to check for secondary and tertiary button styles with appropriate warnings

#### NEW

- Added support for multiple email templates stored in ~/.config/mdtosendy/templates/* directories
- Added --template NAME flag (short: -t) to specify which template to use when processing emails
- Added --create-template NAME flag (short: -c) to create new template directories with default files
- Added --parent NAME flag to create child templates that inherit from parent templates
- Added template-specific config.yml files that override base config values
- Added automatic migration of old template files from root config directory to templates/default on first run
- Added parent template support: templates can specify a parent template and inherit config and files
- Added find_template_file helper that automatically falls back to parent template files if child doesn't have them
- Added --dev flag to generate email-dev.html for template development with linked CSS
- Email-dev.html uses actual email-template.html structure for accurate preview
- Template info table in dev file shows template name, path, and CSS file path
- Email-dev.html now includes footer section with sample footer text if none is configured
- Signature text in dev file supports <br> tags for line breaks (newlines converted to <br>)
- Footer text in dev file supports <br> tags for line breaks (newlines converted to <br>)
- Added support for .button.secondary and .button.tertiary classes in CSS for alternative button styles
- Added CSS aliases: .btn (for .button), .btn.alt (for .button.secondary), .btn.alt2 (for .button.tertiary)
- Button conversion now handles all button variants (primary, secondary, tertiary) with proper style selection based on classes

#### IMPROVED

- Backwards compatibility: existing template files in root directory are automatically migrated to templates/default
- Template creation: --create-template with --parent creates child templates with parent config commented for reference
- Error messages now point to template-specific file locations instead of root config directory
- Help text updated to document new template system and flags
- Backwards compatible: still supports explicit 'element td' selectors for table padding, but now also extracts from element margin/padding

#### FIXED

- CSS stylesheet link is now properly added to email-dev.html head section
- Email-dev.html now includes wrapper and content-wrapper classes on tables so CSS styling applies correctly
- Content wrapper table in dev file now matches actual email styling with dark background from CSS

### 1.0.4

2025-12-30 05:41

#### CHANGED

- Template files (HTML and CSS) are now loaded from template-specific directories instead of root config directory
- Config loading now merges base config with template-specific config, with template config taking precedence
- Template config files support parent key to create child templates that inherit and override parent settings
- CSS margin and padding on elements are now automatically converted to table cell padding during email generation
- Elements can now use margin/padding in CSS file and it will work in both dev preview and final email
- Updated styles.example.css and template CSS files to use margin on elements instead of setting margin/padding to 0
- Removed element td padding selectors from CSS files, replaced with margin on elements
- Template info table shows ~ instead of full home directory path
- Template info table shows full CSS file path (~/.config/mdtosendy/templates/...) instead of relative path

#### NEW

- Added support for multiple email templates stored in ~/.config/mdtosendy/templates/* directories
- Added --template NAME flag (short: -t) to specify which template to use when processing emails
- Added --create-template NAME flag (short: -c) to create new template directories with default files
- Added --parent NAME flag to create child templates that inherit from parent templates
- Added template-specific config.yml files that override base config values
- Added automatic migration of old template files from root config directory to templates/default on first run
- Added parent template support: templates can specify a parent template and inherit config and files
- Added find_template_file helper that automatically falls back to parent template files if child doesn't have them
- Added --dev flag to generate email-dev.html for template development with linked CSS
- Email-dev.html uses actual email-template.html structure for accurate preview
- Template info table in dev file shows template name, path, and CSS file path

#### IMPROVED

- Backwards compatibility: existing template files in root directory are automatically migrated to templates/default
- Template creation: --create-template with --parent creates child templates with parent config commented for reference
- Error messages now point to template-specific file locations instead of root config directory
- Help text updated to document new template system and flags
- Backwards compatible: still supports explicit 'element td' selectors for table padding, but now also extracts from element margin/padding

