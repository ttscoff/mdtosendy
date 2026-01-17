# frozen_string_literal: true

source 'https://rubygems.org'

# Required gem for HTML parsing and manipulation
gem 'nokogiri'

# Optional gems for CDN image upload functionality
# Install only the ones you need based on your CDN type:
# - For S3: aws-sdk-s3
# - For SCP/SFTP: net-scp, net-ssh, ed25519, bcrypt_pbkdf
#   (ed25519 and bcrypt_pbkdf are required if using ed25519 SSH keys, which are common on modern systems)

# S3 upload support
gem 'aws-sdk-s3', '~> 1.0'

# SCP/SFTP upload support
gem 'net-scp', '~> 4.0'
gem 'net-ssh', '~> 7.0'
# Required for ed25519 SSH key support
gem 'ed25519', '~> 1.2'
gem 'bcrypt_pbkdf', '~> 1.0'
