#!/bin/bash
# Installation script for mdtosendy

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="mdtosendy.rb"
INSTALL_NAME="mdtosendy"
CONFIG_DIR="$HOME/.config/mdtosendy"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
info() {
	echo -e "${BLUE}ℹ${NC} $1"
}

success() {
	echo -e "${GREEN}✓${NC} $1"
}

warning() {
	echo -e "${YELLOW}⚠${NC} $1"
}

error() {
	echo -e "${RED}✗${NC} $1"
}

# Check if script exists
if [ ! -f "$SCRIPT_DIR/$SCRIPT_NAME" ]; then
	error "Script not found: $SCRIPT_DIR/$SCRIPT_NAME"
	exit 1
fi

info "Installing mdtosendy..."
echo

# Step 1: Make script executable
info "Making script executable..."
chmod +x "$SCRIPT_DIR/$SCRIPT_NAME"
success "Script is now executable"

# Step 2: Check for required gems
info "Checking for required Ruby gems..."
if ruby -e "require 'nokogiri'" 2>/dev/null; then
	success "nokogiri gem is installed"
else
	error "nokogiri gem is not installed"
	echo "Please install it with: gem install nokogiri"
	exit 1
fi

# Step 3: Find best installation directory
info "Examining PATH to find best installation location..."

# Common installation directories in order of preference
CANDIDATES=(
	"$HOME/usr/local/bin"
	"/opt/homebrew/bin"
	"/usr/local/bin"
	"$HOME/.local/bin"
	"$HOME/bin"
)

# Check which directories exist and are in PATH
INSTALL_DIR=""
for dir in "${CANDIDATES[@]}"; do
	if [ -d "$dir" ] && [[ ":$PATH:" == *":$dir:"* ]]; then
		INSTALL_DIR="$dir"
		break
	fi
done

# If no directory found, use the first candidate that exists or can be created
if [ -z "$INSTALL_DIR" ]; then
	for dir in "${CANDIDATES[@]}"; do
		if [ -d "$dir" ]; then
			INSTALL_DIR="$dir"
			break
		fi
	done

	# If still nothing, use ~/usr/local/bin
	if [ -z "$INSTALL_DIR" ]; then
		INSTALL_DIR="$HOME/usr/local/bin"
	fi
fi

# Ask for confirmation
echo
info "Suggested installation directory: $INSTALL_DIR"
read -p "Install to this directory? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
	read -p "Enter installation directory path: " INSTALL_DIR
	INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}" # Expand ~
fi

# Create directory if it doesn't exist
if [ ! -d "$INSTALL_DIR" ]; then
	info "Creating directory: $INSTALL_DIR"
	mkdir -p "$INSTALL_DIR"
	success "Directory created"
fi

# Step 4: Link script to installation directory
info "Linking script to $INSTALL_DIR/$INSTALL_NAME..."
if [ -L "$INSTALL_DIR/$INSTALL_NAME" ] || [ -f "$INSTALL_DIR/$INSTALL_NAME" ]; then
	warning "File already exists at $INSTALL_DIR/$INSTALL_NAME"
	read -p "Overwrite? (y/N): " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		rm -f "$INSTALL_DIR/$INSTALL_NAME"
	else
		error "Installation cancelled"
		exit 1
	fi
fi

ln -s "$SCRIPT_DIR/$SCRIPT_NAME" "$INSTALL_DIR/$INSTALL_NAME"
success "Script linked to $INSTALL_DIR/$INSTALL_NAME"

# Step 5: Create config directory
info "Creating config directory: $CONFIG_DIR"
mkdir -p "$CONFIG_DIR"
success "Config directory created"

# Step 6: Copy template and example files
info "Copying template and example files..."

# Copy template
if [ -f "$SCRIPT_DIR/email-template.html" ]; then
	cp "$SCRIPT_DIR/email-template.html" "$CONFIG_DIR/email-template.html"
	success "Template copied"
else
	warning "Template file not found: $SCRIPT_DIR/email-template.html"
fi

# Copy example config
if [ -f "$SCRIPT_DIR/config.example.yml" ]; then
	if [ ! -f "$CONFIG_DIR/config.yml" ]; then
		cp "$SCRIPT_DIR/config.example.yml" "$CONFIG_DIR/config.example.yml"
		success "Example config copied"
	else
		warning "config.yml already exists, skipping example config"
	fi
else
	warning "Example config not found: $SCRIPT_DIR/config.example.yml"
fi

# Copy example CSS
if [ -f "$SCRIPT_DIR/styles.example.css" ]; then
	if [ ! -f "$CONFIG_DIR/styles.css" ]; then
		cp "$SCRIPT_DIR/styles.example.css" "$CONFIG_DIR/styles.example.css"
		success "Example CSS copied"
	else
		warning "styles.css already exists, skipping example CSS"
	fi
else
	warning "Example CSS not found: $SCRIPT_DIR/styles.example.css"
fi

# Final instructions
echo
success "Installation complete!"
echo
info "Next steps:"
echo
echo "1. Copy the example files to create your configuration:"
echo "   ${BLUE}cp $CONFIG_DIR/config.example.yml $CONFIG_DIR/config.yml${NC}"
echo "   ${BLUE}cp $CONFIG_DIR/styles.example.css $CONFIG_DIR/styles.css${NC}"
echo
echo "2. Edit the configuration files:"
echo "   ${BLUE}$CONFIG_DIR/config.yml${NC} - Add your Sendy API credentials, email settings, etc."
echo "   ${BLUE}$CONFIG_DIR/styles.css${NC} - Customize your email styles"
echo
echo "3. Test the installation:"
echo "   ${BLUE}mdtosendy --validate${NC}"
echo
echo "4. Generate an email:"
echo "   ${BLUE}mdtosendy your-email.md${NC}"
echo
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
	warning "Note: $INSTALL_DIR is not in your PATH"
	echo "   Add it to your PATH or use the full path: $INSTALL_DIR/$INSTALL_NAME"
	echo
fi
