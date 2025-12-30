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

