module RedmineMsteams

  class Listener < Redmine::Hook::Listener
    def controller_issues_new_after_save(context={})
      issue = context[:issue]

      url = url_for_project issue.project

      return unless url
      return if issue.is_private?

      title = "#{escape issue.project}"
            text = "#{escape issue.author} created [#{escape issue}](#{object_url issue}) #{mentions issue.description}"

      msg=TeamsMessage.new(text,title)
      facts = {
        I18n.t("field_status") => escape(issue.status.to_s),
        I18n.t("field_priority") => escape(issue.priority.to_s),
        I18n.t("field_assigned_to") => escape(issue.assigned_to.to_s)
      }

      facts[I18n.t("field_watcher")] = escape(issue.watcher_users.join(', ')) if Setting.plugin_redmine_msteams[:display_watchers] == 'yes'

      members = Array.new
      begin
    	members << "#{escape issue.author.login}@wafersystems.com" if !issue.author.nil? && issue.author.auth_source_id == 1
        members << "#{escape issue.assigned_to.login}@wafersystems.com" if !issue.assigned_to.nil? && issue.assigned_to.type=='User' && issue.assigned_to.auth_source_id == 1
        
        issue.watcher_users.each{ | watcher |
        	members << "#{escape watcher.login}@wafersystems.com" if watcher.type=='User' && watcher.auth_source_id == 1
        }
        
        members.uniq!
	  rescue Exception => e
		Rails.logger.error(e.message)
	  end
      facts["members"] = escape(members.join(";"))

      msg.addFacts(nil,facts)
      #msg.addAction('Issue',"#{object_url issue}")

      msg.send(url,true)
    end

    def controller_issues_edit_after_save(context={})
      return unless Setting.plugin_redmine_msteams['post_updates'] == '1'

      issue = context[:issue]
      journal = context[:journal]
      #Rails.logger.warn("=========================")
      #Rails.logger.warn(escape(issue.author))
      #Rails.logger.warn(escape(issue.author.login))
      #Rails.logger.warn(escape(issue.assigned_to.login))
      
      #Rails.logger.warn(escape(issue.watcher_users.join(", ")))
      ##Rails.logger.warn(User.find(issue.author_id))
      #Rails.logger.warn("----")
      #Rails.logger.warn(issue.assigned_to)
      ##Rails.logger.warn(User.find(issue.assigned_to))
      ##Rails.logger.warn(issue.watcher_users[0].login)
      ##Rails.logger.warn(issue.watcher_users[0].auth_source_id)
      #Rails.logger.warn("=========================")
      return if issue.is_private? || journal.private_notes?

      return unless url = url_for_project(issue.project)

      title = "#{escape issue.project}"
      text = "#{escape journal.user.to_s} updated [#{escape issue}](#{object_url issue}) #{mentions journal.notes}"
      
      factsTitle = escape journal.notes if journal.notes
      facts = get_facts(journal)
        
      members = Array.new
      begin
    	members << "#{escape issue.author.login}@wafersystems.com" if !issue.author.nil? && issue.author.auth_source_id == 1
        members << "#{escape issue.assigned_to.login}@wafersystems.com" if !issue.assigned_to.nil? && issue.assigned_to.type=='User' && issue.assigned_to.auth_source_id == 1
        
        issue.watcher_users.each{ | watcher |
        	members << "#{escape watcher.login}@wafersystems.com" if watcher.type=='User' && watcher.auth_source_id == 1
        }
        
        members.uniq!
	  rescue Exception => e
		Rails.logger.error(e.message)
	  end
      facts["members"] = escape(members.join(";"))

      msg=TeamsMessage.new(text,title)
      msg.addFacts(factsTitle,facts)
      msg.send(url,true)
    end

    def model_changeset_scan_commit_for_issue_ids_pre_issue_update(context={})
      issue = context[:issue]
      journal = issue.current_journal
      changeset = context[:changeset]

      url = url_for_project issue.project

      return unless url and issue.save
      return if issue.is_private?

      title = "#{escape issue.project}"
            text = "#{escape journal.user.to_s} updated [#{escape issue}](#{object_url issue})"

      repository = changeset.repository

      if Setting.host_name.to_s =~ /\A(https?\:\/\/)?(.+?)(\:(\d+))?(\/.+)?\z/i
        host, port, prefix = $2, $4, $5
        revision_url = Rails.application.routes.url_for(
          :controller => 'repositories',
          :action => 'revision',
          :id => repository.project,
          :repository_id => repository.identifier_param,
          :rev => changeset.revision,
          :host => host,
          :protocol => Setting.protocol,
          :port => port,
          :script_name => prefix
        )
      else
        revision_url = Rails.application.routes.url_for(
          :controller => 'repositories',
          :action => 'revision',
          :id => repository.project,
          :repository_id => repository.identifier_param,
          :rev => changeset.revision,
          :host => Setting.host_name,
          :protocol => Setting.protocol
        )
      end

      facts = get_facts(journal)
      factsTitle = ll(Setting.default_language, :text_status_changed_by_changeset, "[#{escape changeset.comments}](#{revision_url})")

      msg=TeamsMessage.new(text,title)
      msg.addFacts(factsTitle,facts)
      msg.send(url,true)
    end

    def controller_wiki_edit_after_save(context = { })
      return unless Setting.plugin_redmine_msteams['post_wiki_updates'] == '1'

      project = context[:project]
      title = "#{escape project}"
      page = context[:page]

      user = page.content.author
      page_url = "[#{page.title}](#{object_url page})"
      comment = "#{page_url} updated by *#{user}*"

      url = url_for_project project

      if not page.content.comments.empty?
        comment="#{comment}\n\n#{escape page.content.comments}"
      end

      msg=TeamsMessage.new(comment,title)
      msg.send(url,true)
    end

  private
    def get_facts(journal)
      facts = {}
      journal.details.map { |d| facts.merge!(detail_to_field d) }
      return facts
    end

    def escape(msg)
      ERB::Util.h msg.to_s
    end

    def object_url(obj)
      if Setting.host_name.to_s =~ /\A(https?\:\/\/)?(.+?)(\:(\d+))?(\/.+)?\z/i
        host, port, prefix = $2, $4, $5
        Rails.application.routes.url_for(obj.event_url({
          :host => host,
          :protocol => Setting.protocol,
          :port => port,
          :script_name => prefix
        }))
      else
        Rails.application.routes.url_for(obj.event_url({
          :host => Setting.host_name,
          :protocol => Setting.protocol
        }))
      end
    end

    def url_for_project(proj)
      return nil if proj.blank?

      cf = ProjectCustomField.find_by_name("Teams URL")

      cv = proj.custom_value_for(cf)
      url = (cv.value.blank? ? nil : cv.value rescue nil) ||
            url_for_project(proj.parent) ||
            Setting.plugin_redmine_msteams['msteams_url'].presence

      return url if url && url.start_with?("http")
    end

    def detail_to_field(detail)
      if detail.property == "cf"
        key = CustomField.find(detail.prop_key).name rescue nil
        title = key
      elsif detail.property == "attachment"
        key = "attachment"
        title = I18n.t :label_attachment
      else
        key = detail.prop_key.to_s.sub("_id", "")
        title = I18n.t "field_#{key}"
      end

      value = escape detail.value.to_s

      case key
      when "title", "subject", "description"
      when "tracker"
        tracker = Tracker.find(detail.value) rescue nil
        value = escape tracker.to_s
      when "project"
        project = Project.find(detail.value) rescue nil
        value = escape project.to_s
      when "status"
        status = IssueStatus.find(detail.value) rescue nil
        value = escape status.to_s
      when "priority"
        priority = IssuePriority.find(detail.value) rescue nil
        value = escape priority.to_s
      when "category"
        category = IssueCategory.find(detail.value) rescue nil
        value = escape category.to_s
      when "assigned_to"
        user = User.find(detail.value) rescue nil
        value = escape user.to_s
      when "fixed_version"
        version = Version.find(detail.value) rescue nil
        value = escape version.to_s
      when "attachment"
        attachment = Attachment.find(detail.prop_key) rescue nil
        value = "[#{escape attachment.filename}](#{object_url attachment})" if attachment
      when "parent"
        issue = Issue.find(detail.value) rescue nil
        value = "[#{escape issue}](#{object_url issue})" if issue
      end

      value = "-" if value.empty?

      return { title => value }
    end

    def mentions(text)
      return nil # Don't work in teams api right now
      names = extract_usernames text
      names.present? ? "\nTo: " + names.join(', ') : nil
    end

    def extract_usernames(text = '')
      if text.nil?
        text = ''
      end

      # slack usernames may only contain lowercase letters, numbers,
      # dashes and underscores and must start with a letter or number.
      text.scan(/@[a-z0-9][a-z0-9_\-]*/).uniq
    end
  end

end
