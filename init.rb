module AutomaticResourcesBootstrap
  def automatic_resources(*resources, &block)
    @resources = resources.map { |r| r.to_s }
    include AutomaticResources
    instance_eval(&block) if block_given?
  end
end

ApplicationController.extend(AutomaticResourcesBootstrap)

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
    def param_name_for_resource(resource)
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

    target.resources.each do |resource|
      method = target.finder_method_name_for_resource(resource)
      target.module_eval(<<-END)
        def #{method}
          #{target.var_name_for_resource(resource)} ||= object('#{resource}')
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
        def #{method}
          #{var_name} ||= scope('#{resource}').all
        end
        helper_method :#{method}
        protected :#{method}
      END
    end
    
    # Don't generate urls if there aren't nested resources because they are
    # already defined by config/routes.rb if it's a simple controller set up
    # correctly.
    if target.resources.length > 1
      [nil, 'formatted'].each do |formatted|
        ['path', 'url'].each do |suffix|
          route_part = target.route_part_for_resource(target.controller_resource)
          plural_route_part = target.plural_route_part_for_resource(target.controller_resource)
          target.module_eval(<<-END)
            def #{[formatted, route_part, suffix].compact.join('_')}(item, *args)
              generate_url(#{formatted.inspect}, nil, '#{route_part}', '#{suffix}', item, args)
            end
            def #{[formatted, 'edit', route_part, suffix].compact.join('_')}(item, *args)
              generate_url(#{formatted.inspect}, 'edit', '#{route_part}', '#{suffix}', item, args)
            end
            def #{[formatted, 'new', route_part, suffix].compact.join('_')}(*args)
              generate_url(#{formatted.inspect}, 'new', '#{route_part}', '#{suffix}', nil, args)
            end
            def #{[formatted, plural_route_part, suffix].compact.join('_')}(*args)
              generate_url(#{formatted.inspect}, nil, '#{plural_route_part}', '#{suffix}', nil, args)
            end
            helper_method :#{[formatted, route_part, suffix].compact.join('_')}
            helper_method :#{[formatted, 'edit', route_part, suffix].compact.join('_')}
            helper_method :#{[formatted, 'new', route_part, suffix].compact.join('_')}
            helper_method :#{[formatted, plural_route_part, suffix].compact.join('_')}
            protected :#{[formatted, route_part, suffix].compact.join('_')}
            protected :#{[formatted, 'edit', route_part, suffix].compact.join('_')}
            protected :#{[formatted, 'new', route_part, suffix].compact.join('_')}
            protected :#{[formatted, plural_route_part, suffix].compact.join('_')}
          END
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

  private

  def resource_param(resource)
    params[self.class.param_name_for_resource(resource)]
  end

  def active_resources
    self.class.resources.select { |r| has_resource?(r) }
  end

  def has_resource?(resource)
    if resource == self.class.controller_resource
      true
    else
      not params[self.class.param_name_for_resource(resource)].blank?
    end
  end

  def parent
    object(parent_resource)
  end

  def object(resource = controller_resource)
    scope(resource).send(self.class.finder_method_on_resource(resource), resource_param(resource))
  end

  def scope(resource = controller_resource)
    scope = nil
    if parent = parent_resource(resource)
      scope = send(self.class.finder_method_name_for_resource(parent))
      scope = scope.send(self.class.collection_method_on_resource(resource))
    else
      scope = self.class.class_for_resource(resource)
    end
    scope = self.class.scope_names_for_resource(resource).inject(scope) do |result, scope_name|
      result.send(scope_name)
    end
    scope
  end

  def parent_resource(above = nil)
    self.class.resources[0...-1].reverse.find do |resource| 
      if above
        above = nil if resource == above
      else
        has_resource?(resource)
      end
    end
  end

  def generate_url(formatted, prefix, name, suffix, item, extra_args)
    parts = active_resources[0...-1]
    bypass = parts.empty?
    parts = parts.map { |r| self.class.route_part_for_resource(r) }
    method = [formatted, prefix, parts, name, suffix].flatten.compact.join('_')
    args = active_resources[0...-1].map do |r| 
      send(self.class.finder_method_name_for_resource(r))
    end
    args.push item if item
    args = args + extra_args unless extra_args.blank?
    if bypass
      # This only happens if we have no parent resources. It's basically just
      # bypassing the original named url (because it's been overwritten)
      opts = args.extract_options!
      opts[:id] = args unless args.empty?
      url_for(send("hash_for_#{ method }", opts))
    else
      send(method, *args)
    end
  end

end
