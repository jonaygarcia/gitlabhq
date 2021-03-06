module Projects
  class ForkService < BaseService
    def execute
      new_params = {
        forked_from_project_id: @project.id,
        visibility_level:       allowed_visibility_level,
        description:            @project.description,
        name:                   @project.name,
        path:                   @project.path,
        shared_runners_enabled: @project.shared_runners_enabled,
        namespace_id:           @params[:namespace].try(:id) || current_user.namespace.id
      }

      if @project.avatar.present? && @project.avatar.image?
        new_params[:avatar] = @project.avatar
      end

      new_project = CreateService.new(current_user, new_params).execute
      return new_project unless new_project.persisted?

      builds_access_level = @project.project_feature.builds_access_level
      new_project.project_feature.update_attributes(builds_access_level: builds_access_level)

      refresh_forks_count

      link_fork_network(new_project)

      new_project
    end

    private

    def fork_network
      if @project.fork_network
        @project.fork_network
      elsif forked_from_project = @project.forked_from_project
        # TODO: remove this case when all background migrations have completed
        # this only happens when a project had a `forked_project_link` that was
        # not migrated to the `fork_network` relation
        forked_from_project.fork_network || forked_from_project.create_root_of_fork_network
      else
        @project.create_root_of_fork_network
      end
    end

    def link_fork_network(new_project)
      fork_network.fork_network_members.create(project: new_project,
                                               forked_from_project: @project)
    end

    def refresh_forks_count
      Projects::ForksCountService.new(@project).refresh_cache
    end

    def allowed_visibility_level
      project_level = @project.visibility_level

      if Gitlab::VisibilityLevel.non_restricted_level?(project_level)
        project_level
      else
        Gitlab::VisibilityLevel.highest_allowed_level
      end
    end
  end
end
