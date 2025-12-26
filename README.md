# mdtosendy

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

A Ruby script that converts Markdown files to email-ready HTML and plain text, with automatic inline styling for maximum email client compatibility. Designed to work with [Sendy](https://sendy.co/) for campaign creation, but can be used standalone to generate HTML emails.

## Features

- 📝 **Markdown to HTML conversion** - Write emails in Markdown, get beautiful HTML output
- 🎨 **CSS to inline styles** - Maintain styles in CSS files, automatically converted to inline styles for email compatibility
- 📧 **Sendy integration** - Automatically create and schedule campaigns in Sendy
- 🔧 **Fully configurable** - Customize templates, styles, and settings via YAML and CSS files
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

**Combine flags:**
```bash
mdtosendy --validate --preview your-email.md
# or
mdtosendy -v -p your-email.md
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
- **Template settings**: `header_image_url`, `header_image_alt`, `header_image_width`, `header_image_height`, `signature_image_url`, `signature_image_alt`, `signature_image_width`, `signature_image_height`, `signature_text`, `primary_footer`, `footer_text`
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

## Configuration

### Configuration File (`config.yml`)

Located at `~/.config/mdtosendy/config.yml`, organized into sections:

- **sendy**: API URL, API key, brand ID, list IDs
- **email**: From name, from email, reply-to address
- **campaign**: Tracking settings, timezone
- **template**: Header image, signature, primary footer, URLs, and template variables
- **paths**: File paths for template and styles
- **markdown**: Markdown processor to use (default: `apex`). See [Prerequisites](#prerequisites) for installation options.

### Styles File (`styles.css`)

Located at `~/.config/mdtosendy/styles.css`, supports styling for:

- **Typography**: `h1`, `h2`, `h3`, `p`, `strong`, `em`
- **Links**: `a`, `a.button`
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

## File Locations

All configuration and template files are stored in:
- `~/.config/mdtosendy/config.yml` - Configuration file
- `~/.config/mdtosendy/styles.css` - CSS styles
- `~/.config/mdtosendy/email-template.html` - Email template

The script itself can be installed anywhere and will automatically find these files in your home directory's config folder.

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

## Development

For visual CSS editing, use the `email-dev.html` file in the project directory. It links to your CSS file and allows you to see changes in real-time.

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
