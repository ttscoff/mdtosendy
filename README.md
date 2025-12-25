# mdtosendy

A Ruby script that converts Markdown files to email-ready HTML and plain text, with automatic inline styling for maximum email client compatibility. Designed to work with [Sendy](https://sendy.co/) for campaign creation, but can be used standalone to generate HTML emails.

## Features

- 📝 **Markdown to HTML conversion** - Write emails in Markdown, get beautiful HTML output
- 🎨 **CSS to inline styles** - Maintain styles in CSS files, automatically converted to inline styles for email compatibility
- 📧 **Sendy integration** - Automatically create and schedule campaigns in Sendy
- 🔧 **Fully configurable** - Customize templates, styles, and settings via YAML and CSS files
- ✅ **Validation** - Built-in validation for configuration and styles
- 👀 **Preview mode** - Preview generated emails in your browser before sending
- 📦 **Easy installation** - One-command install via curl

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

Your Markdown file can include YAML frontmatter for Sendy campaign creation:

```markdown
---
title: My Email Subject
publish_date: 2024-01-15 10:00:00
status: draft
---

# Email Content

Your email content here...
```

- `title` - Required for Sendy campaign creation
- `publish_date` - Schedule the campaign (format: YYYY-MM-DD HH:MM:SS)
- `status: draft` - Create a draft campaign instead of scheduling

If `title` is present in the frontmatter, the script will automatically create a Sendy campaign (unless `--preview` is used).

## Configuration

### Configuration File (`config.yml`)

Located at `~/.config/mdtosendy/config.yml`, organized into sections:

- **sendy**: API URL, API key, brand ID, list IDs
- **email**: From name, from email, reply-to address
- **campaign**: Tracking settings, timezone
- **template**: Header image, signature, URLs, and template variables
- **paths**: File paths for template and styles
- **markdown**: Markdown processor to use (default: `apex`). See [Markdown Processors](#markdown-processors) for options.

### Styles File (`styles.css`)

Located at `~/.config/mdtosendy/styles.css`, supports styling for:

- **Typography**: `h1`, `h2`, `h3`, `p`, `strong`, `em`
- **Links**: `a`, `a.button`
- **Images**: `img`, `img.full-width`, `img.float-left`, `img.float-right`
- **Lists**: `ul`, `ol`, `li`, `li.bullet`, `li.content`
- **Layout**: `body`, `.wrapper`, `.content-wrapper`
- **Components**: `.footer`, `.signature`

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
- And more...

See the example files for a complete list of available variables.

## Requirements

- Ruby (with `nokogiri` gem installed)
- A Markdown processor (see [Markdown Processors](#markdown-processors) below)
- Git (for installation via bootstrap script)

Install the required gem:
```bash
gem install nokogiri
```

### Markdown Processors

The script supports any Markdown processor that can be called from the command line. The recommended processor is **[Apex](https://github.com/ApexMarkdown/apex)**, which is the default.

**Alternative processors:**
- **[Kramdown](https://kramdown.gettalong.org/)** - Supports IALs (Inline Attribute Lists) for creating buttons, e.g., `[Button Text](url){: .button}`
- **[MultiMarkdown](https://fletcher.github.io/Multimarkdown-6/)** - Supports image attributes for styling images

Configure your preferred processor in `~/.config/mdtosendy/config.yml`:
```yaml
markdown:
  processor: apex  # or kramdown, multimarkdown, etc.
```

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

See the repository for license information.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Links

- Repository: [https://github.com/ttscoff/mdtosendy](https://github.com/ttscoff/mdtosendy)
- Sendy: [https://sendy.co/](https://sendy.co/)
