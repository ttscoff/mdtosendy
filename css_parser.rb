#!/usr/bin/env ruby
# frozen_string_literal: true

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
    css_content = css_content.gsub(/\/\*.*?\*\//m, '')

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

