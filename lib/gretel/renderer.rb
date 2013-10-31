module Gretel
  class Renderer
    DEFAULT_OPTIONS = {
      style: :default,
      pretext: "",
      posttext: "",
      separator: "",
      autoroot: true,
      display_single_fragment: false,
      link_current: false,
      semantic: false,
      class: "breadcrumbs",
      current_class: "current",
      id: nil,
      transform_current_path: true
    }

    DEFAULT_STYLES = {
      default: { container_tag: :div, separator: " &rsaquo; " },
      ol: { container_tag: :ol, fragment_tag: :li },
      ul: { container_tag: :ul, fragment_tag: :li },
      bootstrap: { container_tag: :ol, fragment_tag: :li, class: "breadcrumb", current_class: "active" }
    }


    def initialize(context, breadcrumb_key, *breadcrumb_args)
      @context = context
      @breadcrumb_key = breadcrumb_key
      @breadcrumb_args = breadcrumb_args
    end

    # Renders the breadcrumbs HTML.
    def render(options)
      options = options_for_render(options)
      links = links_for_render(options)

      return "" if links.empty?

      # Array to hold the HTML fragments
      fragments = []

      # Loop through all but the last (current) link and build HTML of the fragments
      links[0..-2].each do |link|
        fragments << render_fragment(options[:fragment_tag], link.text, link.url, options[:semantic])
      end

      # The current link is handled a little differently, and is only linked if specified in the options
      current_link = links.last
      fragments << render_fragment(options[:fragment_tag], current_link.text, (options[:link_current] ? current_link.url : nil), options[:semantic], class: options[:current_class])

      # Build the final HTML
      html = (options[:pretext] + fragments.join(options[:separator]) + options[:posttext]).html_safe
      content_tag(options[:container_tag], html, id: options[:id], class: options[:class])
    end

    # Yields links with applied options.
    def yield_links(options = {})
      options = options_for_render(options)
      yield links_for_render(options)
    end

    # Returns the parent breadcrumb.
    def parent_breadcrumb(options = {})
      options = options_for_render(options)
      links_for_render(options)[-2]
    end

    # Yields the parent breadcrumb if any.
    def yield_parent_breadcrumb(options = {})
      if parent = parent_breadcrumb(options)
        yield parent
      end
    end

    # Proxy for +context.link_to+ that can be overridden by plugins.
    def breadcrumb_link_to(name, url, options = {})
      context.link_to(name, url, options)
    end

    private

    attr_reader :context, :breadcrumb_key, :breadcrumb_args

    # Returns merged options for rendering breadcrumbs.
    def options_for_render(options = {})
      style = options_for_style(options[:style] || DEFAULT_OPTIONS[:style])
      DEFAULT_OPTIONS.merge(style).merge(options)
    end

    # Returns options for the given +style_key+ and raises an exception if it's not found.
    def options_for_style(style_key)
      if style = self.class.styles[style_key]
        style
      else
        raise ArgumentError, "Breadcrumbs style #{style_key.inspect} not found. Use any of #{self.class.styles.keys.inspect}."
      end
    end

    # Array of links with applied options.
    def links_for_render(options = {})
      out = links.dup

      # Handle autoroot
      if options[:autoroot] && out.map(&:key).exclude?(:root) && Gretel::Crumbs.crumb_defined?(:root)
        out.unshift *Gretel::Crumb.new(context, :root).links
      end

      # Set current link to actual path
      if options[:transform_current_path] && out.any? && request
        out.last.url = request.fullpath
      end

      # Handle show root alone
      if out.size == 1 && !options[:display_single_fragment]
        out.shift
      end

      out
    end

    # Array of links for the path of the breadcrumb.
    # Also reloads the breadcrumb configuration if needed.
    def links
      @links ||= if @breadcrumb_key.present?
        # Reload breadcrumbs configuration if needed
        Gretel::Crumbs.reload_if_needed

        # Get breadcrumb set by the `breadcrumb` method
        crumb = Gretel::Crumb.new(context, breadcrumb_key, *breadcrumb_args)

        # Links of first crumb
        links = crumb.links.dup
        
        # Get parent links
        links.unshift *parent_links_for(crumb)

        # Set last link to current
        links.last.try(:current!)

        links
      else
        []
      end
    end

    # Returns parent links for the crumb.
    def parent_links_for(crumb)
      links = []
      while crumb = crumb.parent
        links.unshift *crumb.links
      end
      links
    end

    # Renders HTML for a breadcrumb fragment, i.e. a breadcrumb link.
    def render_fragment(fragment_tag, text, url, semantic, options = {})
      if semantic
        render_semantic_fragment(fragment_tag, text, url, options)
      else
        render_nonsemantic_fragment(fragment_tag, text, url, options)
      end
    end

    # Renders semantic fragment HTML.
    def render_semantic_fragment(fragment_tag, text, url, options = {})
      if fragment_tag
        text = content_tag(:span, text, itemprop: "title")
        text = breadcrumb_link_to(text, url, itemprop: "url") if url.present?
        content_tag(fragment_tag, text, class: options[:class], itemscope: "", itemtype: "http://data-vocabulary.org/Breadcrumb")
      elsif url.present?
        content_tag(:div, breadcrumb_link_to(content_tag(:span, text, itemprop: "title"), url, class: options[:class], itemprop: "url"), itemscope: "", itemtype: "http://data-vocabulary.org/Breadcrumb")
      else
        content_tag(:div, content_tag(:span, text, class: options[:class], itemprop: "title"), itemscope: "", itemtype: "http://data-vocabulary.org/Breadcrumb")
      end
    end

    # Renders regular, non-semantic fragment HTML.
    def render_nonsemantic_fragment(fragment_tag, text, url, options = {})
      if fragment_tag
        text = breadcrumb_link_to(text, url) if url.present?
        content_tag(fragment_tag, text, class: options[:class])
      elsif url.present?
        breadcrumb_link_to(text, url, class: options[:class])
      elsif options[:class].present?
        content_tag(:span, text, class: options[:class])
      else
        text
      end
    end

    # Proxy to view context
    def method_missing(method, *args, &block)
      context.send(method, *args, &block)
    end

    class << self
      include Resettable
      
      # Registers a style for later use.
      # 
      #   Gretel::Renderer.register_style :ul, { container_tag: :ul, fragment_tag: :li }
      def register_style(style_key, options)
        styles[style_key] = options
      end

      # Hash of registered styles.
      def styles
        @styles ||= DEFAULT_STYLES
      end
    end
  end
end