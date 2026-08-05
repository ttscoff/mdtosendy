# mdtosendy

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

A Ruby script that converts Markdown files to email-ready HTML and plain text, with automatic inline styling for maximum email client compatibility. Designed to work with [Sendy](https://sendy.co/) for campaign creation, but can be used standalone to generate HTML emails.

## Features

- 📝 **Markdown to HTML conversion** - Write emails in Markdown, get beautiful HTML output
- 🎨 **CSS to inline styles** - Maintain styles in CSS files, automatically converted to inline styles for email compatibility
- 📧 **Sendy integration** - Automatically create and schedule campaigns in Sendy
- 📤 **Test email sending** - Send test emails directly via SMTP without creating campaigns
- 🖼️ **CDN image upload** - Automatically upload local images to CDN (S3, SCP, or SFTP) and replace URLs
- 🔧 **Fully configurable** - Customize templates, styles, and settings via YAML and CSS files
- 🎭 **Multi-template system** - Create multiple email templates with parent/child inheritance
- 🎨 **Button variants** - Support for primary, secondary, and tertiary button styles
- 🛠️ **Development mode** - Generate dev preview files with linked CSS for easy styling
- ✅ **Validation** - Built-in validation for configuration and styles
- 👀 **Preview mode** - Preview generated emails in your browser before sending
- 📦 **Easy installation** - One-command install via curl

## Prerequisites

Before installing mdtosendy, you'll need:

### Ruby and Nokogiri

mdtosendy requires Ruby with the `nokogiri` gem installed for HTML parsing and manipulation.

**Install nokogiri:**
```bash
gem install nokogiri
```

If you encounter installation issues, you may need to install system dependencies first. On macOS with Homebrew:
```bash
brew install libxml2
gem install nokogiri
```

### Markdown Processor

mdtosendy requires a Markdown processor to convert Markdown to HTML. The recommended processor is **[Apex](https://github.com/ApexMarkdown/apex)**.

**Install Apex:**
```bash
# Using Homebrew (macOS):
brew install apex

# Or clone from GitHub:
git clone https://github.com/ApexMarkdown/apex.git
# Then add the apex binary to your PATH
```

**Alternative Markdown processors:**

- **[Kramdown](https://kramdown.gettalong.org/)** - Supports IALs (Inline Attribute Lists) for creating buttons:
  ```bash
  gem install kramdown
  ```

- **[MultiMarkdown](https://fletcher.github.io/Multimarkdown-6/)** - Supports image attributes:
  ```bash
  # Using Homebrew (macOS):
  brew install multimarkdown

  # Or download from: https://github.com/fletcher/MultiMarkdown-6/releases
  ```

Configure your preferred processor in `~/.config/mdtosendy/config.yml`:
```yaml
markdown:
  processor: apex  # or kramdown, multimarkdown, etc.
```

## Installation

### Quick Install (Recommended)

Install mdtosendy with a single command:

```bash
curl -s https://github.com/ttscoff/mdtosendy/raw/main/bootstrap.sh | bash
```

This will:
- Clone the repository to `~/mdtosendy` (or a directory of your choice)
- Run the installation script
- Link `mdtosendy` to your PATH
- Set up configuration files in `~/.config/mdtosendy/`

### Updating

To update an existing installation, you have two options:

**Option 1: Using the `--update` flag (Recommended)**

You can update using the bootstrap script's `--update` flag:

```bash
# If you saved bootstrap.sh locally:
./bootstrap.sh --update

# Or run directly via curl:
curl -s https://github.com/ttscoff/mdtosendy/raw/main/bootstrap.sh | bash -s -- --update
```

The `--update` flag will:
- Find the installed `mdtosendy` script (following symlinks)
- Navigate to the repository directory
- Run `git pull` to get the latest changes
- Re-run `install.sh` to update the symlink if needed

**Option 2: Manual update**

```bash
# Find where mdtosendy is installed (follow the symlink)
cd $(dirname $(readlink -f $(which mdtosendy)))
# Or if you know the install directory:
cd ~/mdtosendy

# Pull the latest changes
git pull

# Optionally re-run install.sh to update the symlink
./install.sh
```

For more detailed installation instructions, see [INSTALL.md](INSTALL.md).

## Quick Start

1. **Install mdtosendy** (see Installation above)

2. **Set up your configuration:**
   ```bash
   cp ~/.config/mdtosendy/config.example.yml ~/.config/mdtosendy/config.yml
   cp ~/.config/mdtosendy/styles.example.css ~/.config/mdtosendy/styles.css
   ```

3. **Edit your configuration:**
   - `~/.config/mdtosendy/config.yml` - Add your Sendy API credentials, email settings, etc.
   - `~/.config/mdtosendy/styles.css` - Customize your email styles

4. **Validate your setup:**
   ```bash
   mdtosendy --validate
   ```

5. **Generate your first email:**
   ```bash
   mdtosendy your-email.md
   ```

## Usage

### Basic Usage

Generate HTML and plain text email files from a Markdown file:

```bash
mdtosendy your-email.md
```

This creates:
- `your-email.html` - HTML version with inline styles
- `your-email.txt` - Plain text version

### Command-Line Options

**Validate configuration and styles:**
```bash
mdtosendy --validate
# or
mdtosendy -v
```

**Preview generated HTML in browser:**
```bash
mdtosendy --preview your-email.md
# or
mdtosendy -p your-email.md
```

**Use a specific template:**
```bash
mdtosendy --template mytemplate your-email.md
# or
mdtosendy -t mytemplate your-email.md
```

**Create a new template:**
```bash
mdtosendy --create-template mytemplate
# or
mdtosendy -c mytemplate
```

**Create a child template:**
```bash
mdtosendy --create-template darktheme --parent mytemplate
```

**Generate development preview:**
```bash
mdtosendy --dev --template mytemplate
```

**Send test email directly (bypasses Sendy):**
```bash
mdtosendy --test-send your-email@example.com your-email.md
```

This sends a test email directly via SMTP without creating a Sendy campaign. Requires SMTP configuration in `config.yml` (see [SMTP Configuration](#smtp-configuration) below).

**Combine flags:**
```bash
mdtosendy --validate --preview your-email.md
# or
mdtosendy -v -p your-email.md
```

### Multiple files

Pass multiple Markdown files or a glob. Files are processed in order; shared flags apply to each. Processing stops on the first error.

```bash
mdtosendy a.md b.md
mdtosendy emails/*.md
mdtosendy -t marked --preview draft1.md draft2.md
```

**Show help:**
```bash
mdtosendy --help
# or
mdtosendy -h
```

### Markdown File Format

Your Markdown file can include YAML frontmatter for Sendy campaign creation and to override configuration settings:

```markdown
---
title: My Email Subject
publish_date: 2024-01-15 10:00:00
status: draft
---

# Email Content

Your email content here...
```

**Campaign Settings:**
- `title` - Required for Sendy campaign creation
- `publish_date` - Schedule the campaign (format: YYYY-MM-DD HH:MM:SS)
- `status: draft` - Create a draft campaign instead of scheduling

If `title` is present in the frontmatter, the script will automatically create a Sendy campaign (unless `--preview` is used).

**Overriding Configuration:**

You can override any configuration setting from `config.yml` directly in the frontmatter. This is useful for per-email customization without modifying your base configuration.

**Example - Override header image:**
```markdown
---
title: Test Email
status: draft
header_image_url: 'https://marked2app.com/img/email/marked3emailheader2_02.jpg'
---

# Email Content
```

**Supported override keys:**
- **Template settings**: `header_image_url`, `header_image_alt`, `header_image_width`, `header_image_height`, `signature_image_url`, `signature_image_alt`, `signature_image_width`, `signature_image_height`, `signature_text`, `primary_footer`, `footer_text`, `greeting`, `salutation` (alias for `greeting`)
- **Email settings**: `from_name`, `from_email`, `reply_to`
- **Markdown settings**: `processor`
- **Campaign settings**: `track_opens`, `track_clicks`, `default_timezone`

You can also use nested structure in the frontmatter:
```markdown
---
title: Test Email
template:
  header_image_url: 'https://example.com/header.jpg'
  signature_text: '-Custom Signature'
email:
  from_name: 'Custom Sender'
---
```

Frontmatter values take precedence over values in `config.yml`, allowing you to customize individual emails while maintaining a base configuration.

### Greetings

You can add a personalized greeting to your emails that appears after the header image and before the first paragraph. Greetings support multiple configuration methods:

**1. Default greeting in config:**
Set a default greeting in your `config.yml` using either `greeting` or `salutation` (they are synonymous, `salutation` takes precedence if both are defined):
```yaml
template:
  greeting: 'Hey [Name,fallback=there],'
  # or
  salutation: 'Hey [Name,fallback=there],'
```

**2. Override in YAML frontmatter:**
Override the default greeting for a specific email using either `greeting` or `salutation`:
```markdown
---
title: My Email
greeting: 'Hello everyone,'
# or
salutation: 'Hello everyone,'
---
```

**3. Use liquid tag in markdown:**
Place a `{% greeting %}` or `{% salutation %}` tag anywhere in your markdown to insert the configured greeting at that location (without line breaks):
```markdown
{% greeting %}

This is the email content.
```

Or using the alias:
```markdown
{% salutation %}

This is the email content.
```

**4. Override with liquid tag:**
Provide a custom greeting directly in the tag:
```markdown
{% greeting "Hi there" %}

This is the email content.
```

Or using the alias:
```markdown
{% salutation "Hi there" %}

This is the email content.
```

**Notes:**
- If no `{% greeting %}` tags are found in the markdown and a default greeting is configured, it will be automatically inserted before the first paragraph (spacing handled by table layout).
- If `{% greeting %}` tags are present, the default greeting is not automatically inserted.
- Greetings can contain Markdown or HTML and will be processed accordingly.
- The `[Name,fallback=there]` syntax is a Sendy merge tag that will be replaced when the email is sent.

## Configuration

### Configuration File (`config.yml`)

Located at `~/.config/mdtosendy/config.yml` (base config) and optionally `~/.config/mdtosendy/templates/TEMPLATE_NAME/config.yml` (template-specific), organized into sections:

- **sendy**: API URL, API key, brand ID, list IDs
- **email**: From name, from email, reply-to address
- **campaign**: Tracking settings, timezone
- **template**: Header image, signature, primary footer, URLs, greeting, and template variables
- **paths**: File paths for template and styles
- **markdown**: Markdown processor to use (default: `apex`). See [Prerequisites](#prerequisites) for installation options.
- **cdn**: CDN image upload settings (optional). See [CDN Image Upload](#cdn-image-upload) below.
- **smtp**: SMTP settings for test email sending (optional). See [SMTP Configuration](#smtp-configuration) below.

**Configuration Hierarchy:**
1. Base config (`~/.config/mdtosendy/config.yml`) - Shared settings like Sendy API credentials
2. Template config (`~/.config/mdtosendy/templates/NAME/config.yml`) - Template-specific overrides
3. Child template config - Inherits from parent template, can override parent settings

### Styles File (`styles.css`)

Located at `~/.config/mdtosendy/templates/TEMPLATE_NAME/styles.css` (or `~/.config/mdtosendy/styles.css` for backwards compatibility), supports styling for:

- **Typography**: `h1`, `h2`, `h3`, `p`, `strong`, `em`
- **Links**: `a`, `a.button`, `a.button.secondary`, `a.button.tertiary` (or aliases: `a.btn`, `a.btn.alt`, `a.btn.alt2`)
- **Images**: `img`, `img.full-width`, `img.float-left`, `img.float-right`
- **Lists**: `ul`, `ol`, `li`, `li.bullet`, `li.content`
- **Layout**: `body`, `.wrapper`, `.content-wrapper`
- **Components**: `.footer`, `.signature`, `.primary-footer`

### How CSS to Inline Styles Works

The CSS parser reads your `styles.css` file and converts CSS rules to inline styles. This ensures email client compatibility while keeping your styles maintainable.

**Supported CSS features:**
- Basic selectors (element, class, ID)
- Multiple selectors (comma-separated)
- Standard CSS properties
- Comments (ignored)

**Example:**
```css
h1 {
  font-size: 28px;
  color: #333333;
  font-weight: bold;
}
```

Gets converted to:
```html
<h1 style="font-size: 28px; color: #333333; font-weight: bold;">
```

### Template Variables

The email template (`email-template.html`) uses variable placeholders that are automatically replaced:

- `{{TITLE}}` - Email title (from YAML frontmatter or first h1)
- `{{CONTENT}}` - Processed email content
- `{{BODY_STYLE}}` - Styles from CSS `body` selector
- `{{WRAPPER_STYLE}}` - Styles from CSS `.wrapper` selector
- `{{FONT_FAMILY}}` - Font family from CSS `body` selector
- `{{HEADER_IMAGE_URL}}` - From `template.header_image_url` in config
- `{{SIGNATURE_TEXT}}` - From `template.signature_text` in config
- `{{PRIMARY_FOOTER}}` - Processed primary footer content (from `template.primary_footer` in config)
- And more...

See the example files for a complete list of available variables.

### Primary Footer

The primary footer is an optional section that appears after the signature but before the unsubscribe section. It's useful for product links, promotional content, or other footer information.

**Configuration:**

Add a `primary_footer` key to the `template` section in your `config.yml`:

```yaml
template:
  primary_footer: |
    [![](/mas.jpg)](mas-link "Purchase on the Mac App Store") | [![](/paddle.jpg)](paddle-link "Purchase directly")
```

The primary footer can contain:
- **Markdown**: Links, images, and text formatted in Markdown
- **HTML**: Direct HTML content for more complex layouts

The content is automatically processed and styled using your CSS rules (specifically the `.primary-footer` selector). The footer is centered by default and appears between the signature and the unsubscribe section.

**Styling:**

You can style the primary footer using CSS in your `styles.css`:

```css
.primary-footer {
  text-align: center;
  padding: 20px 0;
  color: #666666;
}
```

## Requirements

See the [Prerequisites](#prerequisites) section above for detailed installation instructions. In summary:

- Ruby (with `nokogiri` gem installed)
- A Markdown processor (Apex recommended, or Kramdown/MultiMarkdown)
- Git (for installation via bootstrap script)

## Templates

mdtosendy supports multiple email templates, each with its own HTML, CSS, and configuration files.

### Template Structure

Templates are stored in `~/.config/mdtosendy/templates/NAME/` directories:
- `email-template.html` - HTML template for the email
- `styles.css` - CSS styles for the template
- `config.yml` - Template-specific configuration (optional)

### Creating Templates

**Create a new template:**
```bash
mdtosendy.rb --create-template mytemplate
```

This creates a new template directory with default files copied from the `default` template.

**Create a child template:**
```bash
mdtosendy.rb --create-template darktheme --parent mytemplate
```

Child templates inherit configuration and files from their parent. If a file doesn't exist in the child, it uses the parent's version.

### Using Templates

Specify which template to use with the `--template` flag:
```bash
mdtosendy.rb --template mytemplate email.md
```

If no template is specified, the `default` template is used.

### Button Variants

Buttons support multiple style variants:

- **Primary button**: `[CTA](url){:.button}` or `[CTA](url){:.btn}`
- **Secondary button**: `[CTA](url){:.button .secondary}` or `[CTA](url){:.btn .alt}`
- **Tertiary button**: `[CTA](url){:.button .tertiary}` or `[CTA](url){:.btn .alt2}`

You can also use button liquid tags with multiple syntaxes:

**Named attributes:**
```markdown
{% button class="primary" text="Click Here" url="https://example.com" %}
{% button text="Click Here" url="https://example.com" %}
```

**Positional arguments:**
```markdown
{% button "Click Here" https://example.com %}
{% button alt "Click Here" https://example.com %}
```

**Reference-style links:**
Button tags support markdown reference-style links. Define your references and use them in button tags:

```markdown
[Markdown Web]: https://forum.brettterpstra.com/t/how-about-a-markdown-web/4412/12

{% button alt "How about a Markdown Web?" [Markdown Web] %}
```

Reference matching is case-insensitive, so `[Markdown Web]`, `[markdown web]`, and `[MARKDOWN WEB]` will all match the same reference definition.

Define styles in your CSS:
```css
a.button {
  /* Primary button styles */
}

a.button.secondary,
a.btn.alt {
  /* Secondary button styles */
}

a.button.tertiary,
a.btn.alt2 {
  /* Tertiary button styles */
}
```

### Image Stack Tag

The `{% stack %}` tag allows you to create a vertical stack of images with no spacing between them. Images are rendered full width of the content area, and each image can optionally have a link.

**Markdown image syntax:**
```markdown
{% stack %}
[![](/images/image1.png)](https://example.com/link1)
[![](/images/image2.png)](https://example.com/link2)
[![](/images/image3.png)](https://example.com/link3)
{% endstack %}
```

You can also include images without links:
```markdown
{% stack %}
[![](/images/image1.png)](https://example.com/link1)
![](/images/image2.png)
[![](/images/image3.png)](https://example.com/link2)
{% endstack %}
```

**YAML syntax:**
```markdown
{% stack type="yaml" %}
images:
  - path: /images/image1.png
    url: https://example.com/link1
  - path: /images/image2.png
    url: https://example.com/link2
  - path: /images/image3.png
{% endstack %}
```

In YAML format, the `url` field is optional. If omitted, the image will not have a link.

**Features:**
- Images are stacked vertically with zero spacing between them
- All images are full width of the content area
- Each image can optionally have a link
- Local images in stacks are automatically uploaded to CDN if configured
- Uses table-based layout for maximum email client compatibility

**Notes:**
- Stack images are automatically excluded from the standard image styling that wraps full-width images in tables
- Images maintain their aspect ratio while being full width
- The stack tag works with both local and remote image URLs

### Development Mode

Generate a development preview file with linked CSS for easier styling:
```bash
mdtosendy.rb --dev --template mytemplate
```

This creates `~/.config/mdtosendy/email-dev.html` with:
- Linked CSS (not inlined) for easy editing
- Sample content showing all elements
- Template information table
- Proper wrapper classes for accurate styling

Edit the CSS file and refresh the browser to see changes immediately.

## CDN Image Upload

mdtosendy can automatically detect local images in your Markdown files, upload them to a CDN, and replace the URLs in the output HTML with CDN URLs. This is useful for ensuring images are accessible in emails without hosting them locally.

### Installation

First, install the required gems using Bundler:

```bash
# If you haven't already, install bundler
gem install bundler

# Install dependencies from Gemfile
bundle install
```

The Gemfile includes:
- `nokogiri` - Required for HTML parsing
- `aws-sdk-s3` - For S3 uploads (if using S3)
- `net-scp` and `net-ssh` - For SCP/SFTP uploads (if using SCP/SFTP)
- `ed25519` and `bcrypt_pbkdf` - Required if your SSH keys use ed25519 (common on modern systems)

You only need to install the gems for the upload method you plan to use. The code handles missing gems gracefully.

**Note:** If you use ed25519 SSH keys (which are common on modern systems), you'll need the `ed25519` and `bcrypt_pbkdf` gems. These are included in the Gemfile and will be installed with `bundle install`.

### Configuration

Add CDN configuration to your `config.yml`:

```yaml
cdn:
  # Base URL for CDN (required)
  url: "https://cdn.markedapp.com"

  # Upload type: s3, scp, or sftp
  type: "s3"

  # For S3: username = access key, password = secret key, path = bucket name
  # For SCP/SFTP: username = SSH username, password = SSH password, path = remote directory
  username: "your-access-key-id"
  password: "your-secret-access-key"
  path: "your-bucket-name"

  # Optional: hostname (required for SCP/SFTP, not used for S3)
  # hostname: "example.com"

  # Optional: port (defaults to 22 for SCP/SFTP, not used for S3)
  # port: 22

  # Optional: subdirectory within bucket/path to store images
  # subdirectory: "images"

  # Optional: AWS region for S3 (defaults to us-east-1)
  # region: "us-west-2"

  # Optional: S3 ACL (e.g., "public-read"). Leave unset if bucket has ACLs disabled.
  # acl: "public-read"
```

### S3 Configuration Example

For AWS S3:

```yaml
cdn:
  url: "https://cdn.example.com"
  type: "s3"
  username: "AKIAIOSFODNN7EXAMPLE"  # AWS Access Key ID
  password: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"  # AWS Secret Access Key
  path: "my-bucket-name"
  subdirectory: "email-images"
  region: "us-west-2"
```

### SCP/SFTP Configuration Example

For SCP or SFTP with password authentication:

```yaml
cdn:
  url: "https://cdn.example.com"
  type: "sftp"  # or "scp"
  hostname: "example.com"
  username: "myuser"
  password: "mypassword"
  path: "/var/www/cdn/images"
  port: 22
  subdirectory: "emails"
```

For SCP or SFTP with SSH key-based authentication (using SSH config alias):

```yaml
cdn:
  url: "https://cdn.example.com"
  type: "scp"  # or "sftp"
  hostname: "dh"  # SSH config alias from ~/.ssh/config
  path: "~/brettterpstra.com/images/email/"
  # username and password are optional when using SSH keys
  # Net::SSH will automatically use settings from ~/.ssh/config
```

### How It Works

1. When processing a Markdown file, mdtosendy scans the HTML for local image references
2. Local images are identified (anything that's not an HTTP/HTTPS URL, data URI, etc.)
3. Each local image is uploaded to your configured CDN
4. Images are renamed with timestamps to avoid conflicts (e.g., `image_20240115143022.jpg`)
5. The image URLs in the output HTML are automatically replaced with CDN URLs

**Example:**

If your Markdown contains:
```markdown
![My Image](./images/photo.jpg)
```

And you have CDN configured, the output HTML will have:
```html
<img src="https://cdn.example.com/images/photo_20240115143022.jpg" alt="My Image">
```

The original file `./images/photo.jpg` will be uploaded to your CDN automatically.

### Notes

- Images are resolved relative to the Markdown file's directory
- If an image file is not found, a warning is displayed and processing continues
- Upload errors are displayed but don't stop email generation
- The feature is optional - if CDN is not configured, local image URLs are left unchanged

## SMTP Configuration

To use the `--test-send` feature, configure SMTP settings in your `config.yml`:

```yaml
smtp:
  host: "smtp.gmail.com"
  port: 587
  domain: "gmail.com"
  user: "me@example.com"
  password: "your-app-password-here"
  auth: "plain"
  starttls: true
```

**Gmail Setup:**

For Gmail, you'll need to:
1. Enable 2-factor authentication
2. Generate an App Password at https://myaccount.google.com/apppasswords
3. Use the App Password (not your regular password) in the configuration

**Alternative Gmail configuration (SSL on port 465):**
```yaml
smtp:
  host: "smtp.gmail.com"
  port: 465
  domain: "gmail.com"
  user: "me@example.com"
  password: "your-app-password-here"
  ssl: true
  starttls: false
```

**Other SMTP providers:**

Most SMTP providers follow a similar pattern. Check your provider's documentation for:
- SMTP host and port
- Authentication method (usually "plain")
- Whether STARTTLS or SSL is required

## File Locations

All configuration and template files are stored in:
- `~/.config/mdtosendy/config.yml` - Base configuration file
- `~/.config/mdtosendy/templates/NAME/` - Template directories
  - `email-template.html` - HTML template
  - `styles.css` - CSS styles
  - `config.yml` - Template-specific configuration (optional)

The script automatically migrates old template files from the root config directory to `templates/default/` on first run for backwards compatibility.

## Validation

The script includes comprehensive validation that checks:

- **Configuration**: Required settings are present and valid
- **Styles**: Essential CSS rules are defined
- **Files**: Template and styles files exist
- **Dependencies**: Markdown processor is available

Run validation with:
```bash
mdtosendy --validate
```

Validation runs automatically when processing emails (with `--validate` flag), but the script will continue processing even if warnings are found. Errors will prevent processing.

## Limitations

- The CSS parser is basic and handles standard CSS properties only
- Complex CSS features (media queries, pseudo-selectors, etc.) are not supported
- All styles are converted to inline styles for maximum email client compatibility


## License

MIT License Copyright (c) 2025 Brett Terpstra

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is furnished
to do so, subject to the following conditions:

The above copyright notice and this permission notice (including the next
paragraph) shall be included in all copies or substantial portions of the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF
OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Links

- Repository: [https://github.com/ttscoff/mdtosendy](https://github.com/ttscoff/mdtosendy)
- Sendy: [https://sendy.co/](https://sendy.co/)
