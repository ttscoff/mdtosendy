# Email Generator - Generalization Guide

This email generator has been refactored to be easily configurable and shareable. The system uses:

1. **Configuration file** (`config.yml`) - For API keys, email settings, and paths
2. **CSS styles file** (`styles.css`) - For all visual styling that gets converted to inline styles
3. **CSS Parser** (`css_parser.rb`) - Converts CSS rules to inline styles for email compatibility

## Setup

1. **Copy the example configuration file:**
   ```bash
   cp config.example.yml config.yml
   ```

2. **Edit `config.yml`** with your settings:
   - Sendy API credentials
   - Email addresses and names
   - Template paths
   - Campaign settings

3. **Copy the example styles file:**
   ```bash
   cp styles.example.css styles.css
   ```

4. **Customize `styles.css`** with your brand colors, fonts, and spacing

## How It Works

### CSS to Inline Styles

The CSS parser reads your `styles.css` file and converts CSS rules to inline styles. This ensures email client compatibility while keeping your styles maintainable.

**Supported CSS features:**
- Basic selectors (element, class, ID)
- Multiple selectors (comma-separated)
- Standard CSS properties
- Comments (ignored)

**Example CSS:**
```css
h1 {
  font-size: 28px;
  color: #333333;
  font-weight: bold;
}

h1 td {
  padding: 0 0 20px 0;
}
```

This gets converted to inline styles like:
```html
<h1 style="font-size: 28px; color: #333333; font-weight: bold;">
```

### Configuration Structure

The `config.yml` file is organized into sections:

- **sendy**: API URL, API key, brand ID, list IDs
- **email**: From name, from email, reply-to address
- **campaign**: Tracking settings, timezone
- **template**: Header image, signature, URLs, and template variables
- **paths**: File paths for template and styles
- **markdown**: Markdown processor to use

### Dynamic Template Variables

The email template (`email-template.html`) uses variable placeholders that are automatically replaced with values from your configuration and CSS:

- `{{TITLE}}` - Email title (from YAML frontmatter or first h1)
- `{{CONTENT}}` - Processed email content
- `{{BODY_STYLE}}` - Styles from CSS `body` selector
- `{{WRAPPER_STYLE}}` - Styles from CSS `.wrapper` selector
- `{{CONTENT_WRAPPER_STYLE}}` - Styles from CSS `.content-wrapper` selector
- `{{FONT_FAMILY}}` - Font family from CSS `body` selector
- `{{HEADER_IMAGE_URL}}` - From `template.header_image_url` in config
- `{{HEADER_IMAGE_ALT}}` - From `template.header_image_alt` in config
- `{{HEADER_IMAGE_WIDTH}}` - From `template.header_image_width` in config
- `{{HEADER_IMAGE_HEIGHT}}` - From `template.header_image_height` in config
- `{{SIGNATURE_IMAGE_URL}}` - From `template.signature_image_url` in config
- `{{SIGNATURE_IMAGE_ALT}}` - From `template.signature_image_alt` in config
- `{{SIGNATURE_IMAGE_WIDTH}}` - From `template.signature_image_width` in config
- `{{SIGNATURE_IMAGE_HEIGHT}}` - From `template.signature_image_height` in config
- `{{SIGNATURE_TEXT}}` - From `template.signature_text` in config
- `{{SIGNATURE_STYLE}}` - Styles from CSS `.signature` or `p` selector
- `{{FOOTER_STYLE}}` - Styles from CSS `.footer` selector
- `{{FOOTER_TEXT_STYLE}}` - Styles from CSS `.footer p` selector

This allows you to customize the entire email appearance through CSS and configuration without editing the template file.

### Styling Elements

The CSS file supports styling for:

- **Typography**: `h1`, `h2`, `h3`, `p`, `strong`, `em`
- **Links**: `a`, `a.button`
- **Images**: `img`, `img.full-width`, `img.float-left`, `img.float-right`
- **Lists**: `ul`, `ol`, `li`, `li.bullet`, `li.content`
- **Layout**: `body`, `.wrapper`, `.content-wrapper`
- **Components**: `.footer`, `.signature`

### Special CSS Selectors

Some selectors are used for specific email table structures:

- `h1 td`, `h2 td`, `h3 td` - Padding for heading table cells
- `p td` - Padding for paragraph table cells
- `a.button td` - Button container styling
- `a.button-wrapper` - Button wrapper padding
- `a.button-fallback` - Fallback link styling below buttons
- `li.bullet` - List item bullet cell
- `li.content` - List item content cell

## Usage

### Basic Usage

```bash
./create_email_refactored.rb your-email.md
```

The script will:
1. Load configuration from `config.yml`
2. Load styles from `styles.css`
3. Convert Markdown to HTML
4. Apply inline styles from CSS
5. Generate HTML and plain text versions
6. Optionally create a Sendy campaign (if YAML frontmatter includes `title`)

### Command-Line Options

**Validate configuration and styles:**
```bash
./create_email_refactored.rb --validate
# or
./create_email_refactored.rb -v
```

This will check:
- Required configuration values are set
- Required CSS styles are defined
- Template and styles files exist
- Markdown processor is available

**Preview generated HTML in browser:**
```bash
./create_email_refactored.rb --preview your-email.md
# or
./create_email_refactored.rb -p your-email.md
```

**Combine flags:**
```bash
./create_email_refactored.rb --validate --preview your-email.md
# or
./create_email_refactored.rb -v -p your-email.md
```

**Show help:**
```bash
./create_email_refactored.rb --help
# or
./create_email_refactored.rb -h
```

## Markdown File Format

Your Markdown file can include YAML frontmatter:

```markdown
---
title: My Email Subject
publish_date: 2024-01-15 10:00:00
status: draft
---

# Email Content

Your email content here...
```

- `title`: Required for Sendy campaign creation
- `publish_date`: Schedule the campaign (format: YYYY-MM-DD HH:MM:SS)
- `status: draft`: Create a draft campaign instead of scheduling

## Customization Tips

1. **Colors**: Update all color values in `styles.css` to match your brand
2. **Fonts**: Change `font-family` values throughout `styles.css`
3. **Spacing**: Adjust `padding` and `margin` values
4. **Buttons**: Customize `a.button` styles for your button design
5. **Template**: Modify `email-template.html` for structural changes

## Migration from Original Script

If you're migrating from the original hardcoded script:

1. Extract your hardcoded values to `config.yml`
2. Extract your inline styles to `styles.css`
3. Use the refactored script instead
4. Test with a sample email to ensure styles match

## Validation

The script includes comprehensive validation that checks:

- **Configuration**: Required settings are present and valid
- **Styles**: Essential CSS rules are defined
- **Files**: Template and styles files exist
- **Dependencies**: Markdown processor is available

Run validation with:
```bash
./create_email_refactored.rb --validate
```

Validation runs automatically when processing emails (with `--validate` flag), but the script will continue processing even if warnings are found. Errors will prevent processing.

## Notes

- The CSS parser is basic and handles standard CSS properties
- Complex CSS features (media queries, pseudo-selectors, etc.) are not supported
- All styles are converted to inline styles for maximum email client compatibility
- The template file (`email-template.html`) uses variable placeholders that are automatically replaced
- Use `--preview` to quickly check how your email looks before sending

