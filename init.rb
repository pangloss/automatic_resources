module AutomaticResourcesBootstrap
  def automatic_resources(*resources, &block)
    if resources.last.to_s != controller_name.singularize
      puts "\nWarning: Automatic Resources primary resource on the #{ controller_name } controller is defined as #{ resources.last.inspect }."
    end
    @resources = resources.map { |r| r.to_s }
    include AutomaticResources
    instance_eval(&block) if block_given?
  end
end

if defined?(ActionController::Base)
  ActionController::Base.extend(AutomaticResourcesBootstrap)
end

module AutomaticResources
  # Settings more likely to need to be changed I've put nearer the top.
  #
  # At some point it would be good to define a full dsl, but I've got other
  # things to do...
  #
  # These methods can be redefined in the block passed to the
  # +automatic_resources+ method:
  #
  # automatic_resources :collection, :category, :item do
  #   def finder_method_on_resource(resource)
  #     case resource
  #     when 'item'
  #       'find'
  #     else
  #       'find_by_param!'
  #     end
  #   end
  # end
  #
  module CustomizationMethods
    # The the parameter to use when finding this resource.
    # ie. if we set it to 'isbn':
    #     User.find(params[:isbn])
    def finder_param_name_for_resource(resource)
      if resource == controller_resource
        'id'
      else
        "#{ route_part_for_resource(resource) }_id"
      end
    end

    # The method called against the scoped collection to find the specific record.
    # ie. For the item resource if we wanted to find by isbn, would set it to
    #     'find_by_isbn' as in the following call:
    #     User.find(:first).items.find_by_isbn(params[:id])
    def finder_method_on_resource(resource)
      'find'
    end

    # Add any number of named scopes.
    # ie. Setting:
    #       resource == 'item' ? ['visible', 'activated'] : []
    #     could result in statements like:
    #       Item.visible.activated.find(:first)
    #       User.find(:first).items.visible.activated.find(:first)
    def scope_names_for_resource(resource)
      []
    end

    # The method that is called against the resource's parent object.
    # ie. For the item resource it would be 'items': 
    #     User.find(:first).items
    def collection_method_on_resource(resource)
      resource.pluralize
    end

    # The actual class. 
    # ie. 'item' becomes Item
    def class_for_resource(resource)
      resource.classify.constantize
    end

    # The part of the named url that represents this resource.
    # ie. for the 'item' resource it would be item in user_item_url
    def route_part_for_resource(resource)
      resource.underscore
    end

    # The part of the named url that represents this resource.
    # ie. for the 'item' resource it would be items in user_items_url
    def plural_route_part_for_resource(resource)
      resource.pluralize.underscore
    end

    # The resource the controller acts upon. For ItemsController it would
    # probably be 'item'
    def controller_resource
      resources.last
    end

    # The name of the generated finder method in the controller. The method is
    # also available as a helper.
    def finder_method_name_for_resource(resource)
      resource.underscore
    end

    # The name of the generated collection method in the controller. The method
    # is also available as a helper.
    def collection_method_name_for_resource(resource)
      finder_method_name_for_resource(resource).pluralize
    end

    # The instance variable that the resource is cached in
    def var_name_for_resource(resource)
      "@#{ resource.underscore }"
    end

    # The instance variable that the collection is cached in
    def var_name_for_collection(resource)
      "@#{ resource.underscore.pluralize }"
    end
  end







  def self.included(target)
    target.extend(ClassMethods)
    target.extend(CustomizationMethods)
    target.extend(Filters)

    target.helper_method :parent

    method = "build_#{ target.finder_method_name_for_resource(target.controller_resource) }"
    target.module_eval(<<-END)
      def #{method}(*args)
        klass = scope(self.class.controller_resource)
        if klass == self.class.class_for_resource(self.class.controller_resource)
          klass.new(*args)
        else
          klass.build(*args)
        end
      end
      helper_method :#{method}
      protected :#{method}
    END

    target.resources.each do |resource|
      method = target.finder_method_name_for_resource(resource)
      var_name = target.var_name_for_resource(resource)
      target.module_eval(<<-END)
        def #{method}
          #{var_name} ||= object('#{resource}')
        end
        helper_method :#{method}
        protected :#{method}
      END

      method = "#{ target.finder_method_name_for_resource(resource) }?"
      target.module_eval(<<-END)
        def #{method}
          has_resource?('#{resource}')
        end
        helper_method :#{method}
        protected :#{method}
      END

      method = target.collection_method_name_for_resource(resource)
      var_name = target.var_name_for_collection(resource)
      target.module_eval(<<-END)
        # The +execute+ option runs the query and caches the result. Without it
        # the scope is returned unexecuted which depending on what the scope is
        # may or may not be an array (proxy) which can be iterated over.  By
        # not executing the scope, further scoping or finder methods can be
        # applied to it before it is executed.
        def #{method}(execute = true)
          if execute
            #{var_name} ||= scope('#{resource}').all
          else
            scope('#{resource}')
          end
        end
        helper_method :#{method}
        protected :#{method}
      END

      ['require', 'sometimes_require'].each do |prefix|
        method = "#{ prefix }_#{ resource.underscore }_filter"
        target.module_eval(<<-END)
          def #{method}
            #{prefix}_resource_filter('#{resource}')
          end
          protected :#{method}
        END
      end
    end
    
    # Don't generate urls if there aren't nested resources because they are
    # already defined by config/routes.rb if it's a simple controller set up
    # correctly.
    target.resources.each do |resource|
      if target.resources.first != resource
        [nil, 'formatted'].each do |formatted|
          ['path', 'url'].each do |suffix|
            route_part = target.route_part_for_resource(resource)
            plural_route_part = target.plural_route_part_for_resource(resource)
            item_optional = ' = nil' unless resource == target.controller_resource
            target.module_eval(<<-END)
              def #{[formatted, route_part, suffix].compact.join('_')}(item#{ item_optional }, *args)
                if item.is_a? Hash
                  args = [item]
                  item = nil
                end
                item ||= self.#{ target.finder_method_name_for_resource(resource) }
                generate_url(#{formatted.inspect}, nil, '#{route_part}', '#{suffix}', '#{ resource }', item, args)
              end
              helper_method :#{[formatted, route_part, suffix].compact.join('_')}
              protected :#{[formatted, route_part, suffix].compact.join('_')}

              def #{[formatted, 'edit', route_part, suffix].compact.join('_')}(item#{ item_optional }, *args)
                if item.is_a? Hash
                  args = [item]
                  item = nil
                end
                item ||= self.#{ target.finder_method_name_for_resource(resource) }
                generate_url(#{formatted.inspect}, 'edit', '#{route_part}', '#{suffix}', '#{ resource }', item, args)
              end
              helper_method :#{[formatted, 'edit', route_part, suffix].compact.join('_')}
              protected :#{[formatted, 'edit', route_part, suffix].compact.join('_')}

              def #{[formatted, 'new', route_part, suffix].compact.join('_')}(*args)
                generate_url(#{formatted.inspect}, 'new', '#{route_part}', '#{suffix}', '#{ resource }', nil, args)
              end
              helper_method :#{[formatted, 'new', route_part, suffix].compact.join('_')}
              protected :#{[formatted, 'new', route_part, suffix].compact.join('_')}

              def #{[formatted, plural_route_part, suffix].compact.join('_')}(*args)
                generate_url(#{formatted.inspect}, nil, '#{plural_route_part}', '#{suffix}', '#{ resource }', nil, args)
              end
              helper_method :#{[formatted, plural_route_part, suffix].compact.join('_')}
              protected :#{[formatted, plural_route_part, suffix].compact.join('_')}
            END
          end
        end
      end
    end
  end

  module ClassMethods
    # The last one should be the controller's main resource
    # ie. ItemsController.resources #=> ['collection', 'category', 'item']
    def resources
      @resources
    end

  end

  module Filters
    def require_resource(resource, options = {})
      filter_method = options.delete(:filter_method) || :before_filter
      send(filter_method, "require_#{ resource }_filter".to_sym, options)
    end

    # Require a resource only if it is included in the url.
    def sometimes_require_resource(resource, options = {})
      filter_method = options.delete(:filter_method) || :before_filter
      send(filter_method, "sometimes_require_#{ resource }_filter".to_sym, options)
    end
  end

  private

  def require_resource_filter(resource)
    if object(resource)
      true
    else
      record_not_found
    end
  end

  def sometimes_require_resource_filter(resource)
    if has_resource?(resource)
      if object(resource)
        true
      else
        record_not_found
      end
    else
      true
    end
  end

  def resource_finder_param(resource)
    params[self.class.finder_param_name_for_resource(resource)]
  end

  def active_resources
    self.class.resources.select { |r| has_resource?(r) }
  end

  def has_resource?(resource)
    if resource == self.class.controller_resource
      true
    else
      not resource_finder_param(resource).blank?
    end
  end

  def parent
    object(parent_resource) if parent_resource
  end

  def object(resource)
    scope(resource).send(self.class.finder_method_on_resource(resource), resource_finder_param(resource))
  end

  def scope_names_for_resource(resource)
    self.class.scope_names_for_resource(resource)
  end

  def scope(resource)
    scope = nil
    if parent = parent_resource(resource)
      scope = send(self.class.finder_method_name_for_resource(parent))
      scope = scope.send(self.class.collection_method_on_resource(resource), false)
    else
      scope = self.class.class_for_resource(resource)
    end
    scopes = [*scope_names_for_resource(resource)].compact
    scope = scopes.inject(scope) do |result, scope_name|
      result.send(scope_name)
    end
    scope
  end

  def parent_resource(above = nil)
    above = nil if above == self.class.controller_resource
    self.class.resources[0...-1].reverse.find do |resource| 
      if above
        above = nil if resource == above
      else
        has_resource?(resource)
      end
    end
  end

  def generate_url(formatted, prefix, name, suffix, resource, item, extra_args)
    index = active_resources.index(resource)
    raise "A route was called for #{ resource }, but #{ resource } is not currently active." unless index
    parts = active_resources[0...index]
    bypass = parts.empty?
    parts = parts.map { |r| self.class.route_part_for_resource(r) }
    method = [formatted, prefix, parts, name, suffix].flatten.compact.join('_')
    args = active_resources[0...index].map do |r| 
      send(self.class.finder_method_name_for_resource(r))
    end
    args.push item if item
    args = args + extra_args unless extra_args.blank?
    if bypass
      # This only happens if we have no parent resources. It's basically just
      # bypassing the original named url (because it's been overwritten)
      opts = args.extract_options!
      opts[:id] = args.to_param unless args.empty?
      url_for(send("hash_for_#{ method }", opts))
    else
      send(method, *args)
    end
  end

end
