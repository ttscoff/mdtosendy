#!/bin/bash
# Bootstrap installer for mdtosendy
# Can be run via: curl -s https://github.com/ttscoff/mdtosendy/raw/main/bootstrap.sh | bash
# Or saved locally and run with: ./bootstrap.sh --update

set -e

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

# Function to show help
show_help() {
	echo "Bootstrap installer for mdtosendy"
	echo
	echo "Usage:"
	echo "  curl -s https://github.com/ttscoff/mdtosendy/raw/main/bootstrap.sh | bash"
	echo "  ./bootstrap.sh [OPTIONS]"
	echo
	echo "Options:"
	echo "  --update, -u    Update existing installation by running git pull"
	echo "  --help, -h      Show this help message"
	echo
	echo "Examples:"
	echo "  # Install mdtosendy"
	echo "  curl -s https://github.com/ttscoff/mdtosendy/raw/main/bootstrap.sh | bash"
	echo
	echo "  # Update existing installation"
	echo "  ./bootstrap.sh --update"
	echo
	echo "For more information, visit: https://github.com/ttscoff/mdtosendy"
}

# Function to find real path of a file (following symlinks)
get_real_path() {
	local file="$1"
	if command -v realpath >/dev/null 2>&1; then
		realpath "$file"
	elif command -v readlink >/dev/null 2>&1; then
		readlink -f "$file" 2>/dev/null || {
			# Fallback for systems without readlink -f
			local dir=$(dirname "$file")
			local base=$(basename "$file")
			cd "$dir" 2>/dev/null || return 1
			local target=$(readlink "$base" 2>/dev/null)
			if [ -n "$target" ]; then
				if [ "${target:0:1}" = "/" ]; then
					get_real_path "$target"
				else
					get_real_path "$dir/$target"
				fi
			else
				echo "$(pwd)/$base"
			fi
		}
	else
		# Last resort: try to resolve manually
		local dir=$(dirname "$file")
		local base=$(basename "$file")
		cd "$dir" 2>/dev/null || return 1
		echo "$(pwd)/$base"
	fi
}

# Function to update existing installation
update_installation() {
	info "Updating mdtosendy installation..."
	echo

	# Try to find mdtosendy in PATH
	if ! command -v mdtosendy >/dev/null 2>&1; then
		error "mdtosendy not found in PATH"
		echo "Please ensure mdtosendy is installed and in your PATH"
		exit 1
	fi

	# Get the real path of the mdtosendy script
	MDTOSENDY_PATH=$(command -v mdtosendy)
	REAL_PATH=$(get_real_path "$MDTOSENDY_PATH")

	if [ ! -f "$REAL_PATH" ]; then
		error "Could not resolve real path of mdtosendy: $MDTOSENDY_PATH"
		exit 1
	fi

	# Get the directory containing the script
	REPO_DIR=$(dirname "$REAL_PATH")

	info "Found installation at: $REPO_DIR"

	# Check if it's a git repository
	if [ ! -d "$REPO_DIR/.git" ]; then
		error "Installation directory is not a git repository: $REPO_DIR"
		echo "Cannot update. Please reinstall using the bootstrap script."
		exit 1
	fi

	# Change to repository directory and pull
	info "Updating repository..."
	cd "$REPO_DIR" || exit 1

	if ! git pull; then
		error "Failed to update repository"
		exit 1
	fi

	success "Repository updated successfully"

	# Re-run install.sh to ensure symlink is up to date
	if [ -f "$REPO_DIR/install.sh" ]; then
		info "Re-running install script to update symlink..."
		"$REPO_DIR/install.sh"
	else
		warning "install.sh not found, skipping symlink update"
	fi

	echo
	success "Update complete!"
}

# Parse arguments
UPDATE_MODE=false
for arg in "$@"; do
	case $arg in
		--update|-u)
			UPDATE_MODE=true
			shift
			;;
		--help|-h)
			show_help
			exit 0
			;;
		*)
			warning "Unknown option: $arg"
			echo "Use --help for usage information"
			exit 1
			;;
	esac
done

# If --update flag is set, run update and exit
if [ "$UPDATE_MODE" = true ]; then
	update_installation
	exit 0
fi

# Normal installation flow
info "Bootstrap installer for mdtosendy"
echo

# Check for required tools
if ! command -v git >/dev/null 2>&1; then
	error "git is not installed"
	echo "Please install git first: https://git-scm.com/downloads"
	exit 1
fi

# Prompt for install directory
DEFAULT_INSTALL_DIR="$HOME/mdtosendy"
info "Installation directory (default: $DEFAULT_INSTALL_DIR)"
read -p "Enter directory path or press Enter for default: " INSTALL_DIR
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}" # Expand ~

# Check if directory exists
if [ -d "$INSTALL_DIR" ]; then
	if [ -d "$INSTALL_DIR/.git" ]; then
		# It's a git repository, offer to update
		warning "Directory already exists and is a git repository: $INSTALL_DIR"
		read -p "Update existing installation? (Y/n): " -n 1 -r
		echo
		if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
			info "Updating existing installation..."
			cd "$INSTALL_DIR" || exit 1
			if ! git pull; then
				error "Failed to update repository"
				exit 1
			fi
			success "Repository updated"
		else
			info "Installation cancelled"
			exit 0
		fi
	else
		# Directory exists but is not a git repository
		warning "Directory already exists but is not a git repository: $INSTALL_DIR"
		read -p "Remove and reinstall? (y/N): " -n 1 -r
		echo
		if [[ $REPLY =~ ^[Yy]$ ]]; then
			info "Removing existing directory..."
			rm -rf "$INSTALL_DIR"
		else
			read -p "Enter a different directory path: " INSTALL_DIR
			INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}" # Expand ~
			if [ -d "$INSTALL_DIR" ]; then
				error "Directory still exists: $INSTALL_DIR"
				exit 1
			fi
		fi
	fi
fi

# Clone repository
info "Cloning repository to $INSTALL_DIR..."
if ! git clone https://github.com/ttscoff/mdtosendy.git "$INSTALL_DIR"; then
	error "Failed to clone repository"
	exit 1
fi
success "Repository cloned successfully"

# Run install.sh from cloned directory
if [ -f "$INSTALL_DIR/install.sh" ]; then
	info "Running install script..."
	cd "$INSTALL_DIR" || exit 1
	chmod +x install.sh
	./install.sh
else
	error "install.sh not found in cloned repository"
	exit 1
fi

echo
success "Bootstrap installation complete!"
echo
info "The repository is installed at: $INSTALL_DIR"
info "You can update it later by running: cd $INSTALL_DIR && git pull"
info "Or use: ./bootstrap.sh --update (if you saved this script locally)"

