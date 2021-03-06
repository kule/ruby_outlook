require "ruby_outlook/version"
require "faraday"
require "uuidtools"
require "json"

module RubyOutlook
  class Client
    # User agent
    attr_reader :user_agent
    # The server to make API calls to.
    # Always "https://outlook.office365.com"
    attr_writer :api_host
    attr_writer :enable_fiddler

    def initialize
      @user_agent = "RubyOutlookGem/" << RubyOutlook::VERSION
      @api_host = "https://outlook.office365.com"
      @enable_fiddler = false
    end

    # method (string): The HTTP method to use for the API call.
    #                  Must be 'GET', 'POST', 'PATCH', or 'DELETE'
    # url (string): The URL to use for the API call. Must not contain
    #               the host. For example: '/api/v2.0/me/messages'
    # token (string): access token
    # params (hash) a Ruby hash containing any query parameters needed for the API call
    # payload (hash): a JSON hash representing the API call's payload. Only used
    #                 for POST or PATCH.
    def make_api_call(method, url, token, params = nil, payload = nil)

      conn_params = {
        :url => 'https://outlook.office365.com'
      }

      if @enable_fiddler
        conn_params[:proxy] = 'http://127.0.0.1:8888'
        conn_params[:ssl] = {:verify => false}
      end

      conn = Faraday.new(conn_params) do |faraday|
        # Uses the default Net::HTTP adapter
        faraday.adapter  Faraday.default_adapter

      end

      conn.headers = {
        'Authorization' => "Bearer #{token}",
        'Accept' => "application/json",

        # Client instrumentation
        # See https://msdn.microsoft.com/EN-US/library/office/dn720380(v=exchg.150).aspx
        'User-Agent' => @user_agent,
        'client-request-id' => UUIDTools::UUID.timestamp_create.to_str,
        'return-client-request-id' => "true"
      }

      case method.upcase
        when "GET"
          response = conn.get do |request|
            request.url url, params
          end
        when "POST"
          conn.headers['Content-Type'] = "application/json"
          response = conn.post do |request|
            request.url url, params
            request.body = JSON.dump(payload)
          end
        when "PATCH"
          conn.headers['Content-Type'] = "application/json"
          response = conn.patch do |request|
            request.url url, params
            request.body = JSON.dump(payload)
          end
        when "DELETE"
          response = conn.delete do |request|
            request.url url, params
          end
      end

      if response.status >= 300
        error_info = response.body.empty? ? '' : JSON.parse(response.body)
        return JSON.dump({
          'ruby_outlook_error' => response.status,
          'ruby_outlook_response' => error_info })
      end

      response.body
    end

    #----- Begin Contacts API -----#

    # token (string): access token
    # view_size (int): maximum number of results
    # page (int): What page to fetch (multiple of view size)
    # fields (array): An array of field names to include in results
    # sort (hash): { sort_on => field_to_sort_on, sort_order => 'ASC' | 'DESC' }
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def get_contacts(token, view_size, page, fields = nil, sort = nil, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/Contacts"
      request_params = {
        '$top' => view_size,
        '$skip' => (page - 1) * view_size
      }

      unless fields.nil?
        request_params['$select'] = fields.join(',')
      end

      unless sort.nil?
        request_params['$orderby'] = sort[:sort_field] + " " + sort[:sort_order]
      end

      get_contacts_response = make_api_call "GET", request_url, token, request_params

      JSON.parse(get_contacts_response)
    end

    # token (string): access token
    # id (string): The Id of the contact to retrieve
    # fields (array): An array of field names to include in results
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def get_contact_by_id(token, id, fields = nil, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/Contacts/" << id
      request_params = nil

      unless fields.nil?
        request_params = { '$select' => fields.join(',') }
      end

      get_contact_response = make_api_call "GET", request_url, token, request_params

      JSON.parse(get_contact_response)
    end

    # token (string): access token
    # payload (hash): a JSON hash representing the contact entity
    # folder_id (string): The Id of the contact folder to create the contact in.
    #                     If nil, contact is created in the default contacts folder.
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def create_contact(token, payload, folder_id = nil, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user))

      unless folder_id.nil?
        request_url << "/ContactFolders/" << folder_id
      end

      request_url << "/Contacts"

      create_contact_response = make_api_call "POST", request_url, token, nil, payload

      JSON.parse(create_contact_response)
    end

    # token (string): access token
    # payload (hash): a JSON hash representing the updated contact fields
    # id (string): The Id of the contact to update.
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def update_contact(token, payload, id, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/Contacts/" << id

      update_contact_response = make_api_call "PATCH", request_url, token, nil, payload

      JSON.parse(update_contact_response)
    end

    # token (string): access token
    # id (string): The Id of the contact to delete.
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def delete_contact(token, id, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/Contacts/" << id

      delete_response = make_api_call "DELETE", request_url, token

      return nil if delete_response.nil? || delete_response.empty?

       JSON.parse(delete_response)
    end

    #----- End Contacts API -----#

    #----- Begin Mail API -----#

    # token (string): access token
    # view_size (int): maximum number of results
    # page (int): What page to fetch (multiple of view size)
    # fields (array): An array of field names to include in results
    # sort (hash): { sort_field: field_to_sort_on, sort_order: 'ASC' | 'DESC' }
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def get_messages(token, view_size, page, fields = nil, sort = nil, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/Messages"
      request_params = {
        '$top' => view_size,
        '$skip' => (page - 1) * view_size
      }

      unless fields.nil?
        request_params['$select'] = fields.join(',')
      end

      unless sort.nil?
        request_params['$orderby'] = sort[:sort_field] + " " + sort[:sort_order]
      end

      get_messages_response = make_api_call "GET", request_url, token, request_params

      JSON.parse(get_messages_response)
    end

    # token (string): access token
    # view_size (int): maximum number of results
    # page (int): What page to fetch (multiple of view size)
    # fields (array): An array of field names to include in results
    # sort (hash): { sort_on => field_to_sort_on, sort_order => 'ASC' | 'DESC' }
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    # folder_id (string): The folder to get mail for. (inbox, drafts, sentitems, deleteditems)
    def get_messages_for_folder(token, view_size, page, fields = nil, sort = nil, user = nil, folder_id)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/MailFolders/#{folder_id}/messages"
      request_params = {
        '$top' => view_size,
        '$skip' => (page - 1) * view_size
      }

      unless fields.nil?
        request_params['$select'] = fields.join(',')
      end

      unless sort.nil?
        request_params['$orderby'] = sort[:sort_field] + " " + sort[:sort_order]
      end

      get_messages_response = make_api_call "GET", request_url, token, request_params

      JSON.parse(get_messages_response)
    end

    # token (string): access token
    # id (string): The Id of the message to retrieve
    # fields (array): An array of field names to include in results
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def get_message_by_id(token, id, fields = nil, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/Messages/" << id
      request_params = nil

      unless fields.nil?
        request_params = { '$select' => fields.join(',') }
      end

      get_message_response = make_api_call "GET", request_url, token, request_params

      JSON.parse(get_message_response)
    end

    # token (string): access token
    # id (string): The Id of the message to retrieve
    # fields (array): An array of field names to include in results
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    # returns JSON array of attachments
    def get_attachment_by_message_id(token, id, fields = nil, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user )) << "/Messages/" << id << "/attachments"
      request_params = nil

      unless fields.nil?
        request_params = { '$select' => fields.join(',') }
      end

      get_message_response = make_api_call "GET", request_url, token, request_params

      JSON.parse(get_message_response)
    end

    # token (string): access token
    # payload (hash): a JSON hash representing the contact entity
    # folder_id (string): The Id of the folder to create the message in.
    #                     If nil, message is created in the default drafts folder.
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def create_message(token, payload, folder_id = nil, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user))

      unless folder_id.nil?
        request_url << "/MailFolders/" << folder_id
      end

      request_url << "/Messages"

      create_message_response = make_api_call "POST", request_url, token, nil, payload

      JSON.parse(create_message_response)
    end

    # token (string): access token
    # payload (hash): a JSON hash representing the updated message fields
    # id (string): The Id of the message to update.
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def update_message(token, payload, id, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/Messages/" << id

      update_message_response = make_api_call "PATCH", request_url, token, nil, payload

      JSON.parse(update_message_response)
    end

    # token (string): access token
    # id (string): The Id of the message to delete.
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def delete_message(token, id, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/Messages/" << id

      delete_response = make_api_call "DELETE", request_url, token

      return nil if delete_response.nil? || delete_response.empty?

      JSON.parse(delete_response)
    end

    # token (string): access token
    # payload (hash): a JSON hash representing the message to send
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def send_message(token, payload, save_to_sentitems = true, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/SendMail"

      # Wrap message in the sendmail JSON structure
      send_mail_json = {
        'Message' => payload,
        'SaveToSentItems' => save_to_sentitems
      }

      send_response = make_api_call "POST", request_url, token, nil, send_mail_json

      return nil if send_response.nil? || send_response.empty?

      JSON.parse(send_response)
    end

    # token (string): access token
    # comment (string): the comment you wish to reply with (can be blank)
    # message_id (string): The Id of the message you are replying to
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def send_reply(token, comment, message_id, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/Messages/" << message_id << "/reply"

      # Wrap message in the sendmail JSON structure
      send_reply_json = {
        'Comment' => comment
      }

      send_reply_response = make_api_call "POST", request_url, token, nil, send_reply_json

      JSON.parse(send_reply_response)
    end

    # token (string): access token
    # comment (string): the comment you wish to include (can be blank)
    # message_id (string): The Id of the message you are replying to
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def create_reply(token, comment, message_id, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/Messages/" << message_id << "/createreply"

      # Wrap message in the sendmail JSON structure
      create_reply_json = {
        'Comment' => comment
      }

      create_reply_response = make_api_call "POST", request_url, token, nil, create_reply_json

      JSON.parse(create_reply_response)
    end

    # token (string): access token
    # comment (string): the comment you wish to reply to all with (can be blank)
    # message_id (string): The Id of the message you are replying to
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def send_reply_all(token, comment, message_id, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/Messages/" << message_id << "/replyall"

      # Wrap message in the sendmail JSON structure
      send_reply_all_json = {
        'Comment' => comment
      }

      send_reply_all_response = make_api_call "POST", request_url, token, nil, send_reply_all_json

      JSON.parse(send_reply_all_response)
    end

    # token (string): access token
    # comment (string): the comment you wish to include (can be blank)
    # message_id (string): The Id of the message you are replying to
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def create_reply_all(token, comment, message_id, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/Messages/" << message_id << "/createreplyall"

      # Wrap message in the sendmail JSON structure
      create_reply_all_json = {
        'Comment' => comment
      }

      create_reply_all_response = make_api_call "POST", request_url, token, nil, create_reply_all_json

      JSON.parse(create_reply_all_response)
    end

    # token (string): access token
    # comment (string): the comment you wish to forward with (can be blank)
    # message_id (string): The Id of the message you are replying to
    # recipients (array of hashes): a array of JSON hashes representing the Recipients to send to
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def send_foward(token, comment, message_id, recipients, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/Messages/" << message_id << "/forward"

      # Wrap message in the sendmail JSON structure
      send_forward_json = {
        'Comment' => comment,
        'ToRecipients' => recipients
      }

      send_forward_response = make_api_call "POST", request_url, token, nil, send_forward_json

      JSON.parse(send_forward_response)
    end

    # token (string): access token
    # comment (string): the comment you wish to include (can be blank)
    # message_id (string): The Id of the message you are replying to
    # recipients (array of hashes): a array of JSON hashes representing the Recipients to be sent to
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def create_foward(token, comment, message_id, recipients, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/Messages/" << message_id << "/createforward"

      # Wrap message in the sendmail JSON structure
      create_forward_json = {
        'Comment' => comment,
        'ToRecipients' => recipients
      }

      create_forward_response = make_api_call "POST", request_url, token, nil, create_forward_json

      JSON.parse(create_forward_response)
    end

    # token (string): access token
    # view_size (int): maximum number of results
    # page (int): What page to fetch (multiple of view size)
    # fields (array): An array of field names to include in results
    # sort (hash): { sort_field: field_to_sort_on, sort_order: 'ASC' | 'DESC' }
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    # folder (string): The parent folder to return only folders within it.
    def get_folders(token, view_size, page, fields = nil, sort = nil, user = nil, folder = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/MailFolders"

      unless folder.blank?
        request_url << "/#{folder}/childfolders"
      end

      request_params = {
        '$top' => view_size,
        '$skip' => (page - 1) * view_size
      }

      unless fields.nil?
        request_params['$select'] = fields.join(',')
      end

      unless sort.nil?
        request_params['$orderby'] = sort[:sort_field] + " " + sort[:sort_order]
      end

      get_folders_response = make_api_call "GET", request_url, access_token, request_params

      JSON.parse(get_folders_response)
    end

    # token (string): access token
    # id (string): The Id of the message to retrieve
    # fields (array): An array of field names to include in results
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def get_folder_by_id(token, id, fields = nil, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/MailFolders/#{id}"

      request_params = nil

      unless fields.nil?
        request_params = { '$select' => fields.join(',') }
      end

      get_folder_response = make_api_call "GET", request_url, token, request_params

      JSON.parse(get_folder_response)
    end

    #----- End Mail API -----#

    #----- Begin Calendar API -----#

    # token (string): access token
    # view_size (int): maximum number of results
    # page (int): What page to fetch (multiple of view size)
    # fields (array): An array of field names to include in results
    # sort (hash): { sort_on => field_to_sort_on, sort_order => 'ASC' | 'DESC' }
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def get_events(token, view_size, page, fields = nil, sort = nil, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/Events"
      request_params = {
        '$top' => view_size,
        '$skip' => (page - 1) * view_size
      }

      unless fields.nil?
        request_params['$select'] = fields.join(',')
      end

      unless sort.nil?
        request_params['$orderby'] = sort[:sort_field] + " " + sort[:sort_order]
      end

      get_events_response = make_api_call "GET", request_url, token, request_params

      JSON.parse(get_events_response)
    end

    # token (string): access token
    # id (string): The Id of the event to retrieve
    # fields (array): An array of field names to include in results
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def get_event_by_id(token, id, fields = nil, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/Events/" << id
      request_params = nil

      unless fields.nil?
        request_params = { '$select' => fields.join(',') }
      end

      get_event_response = make_api_call "GET", request_url, token, request_params

      JSON.parse(get_event_response)
    end

    # token (string): access token
    # window_start (DateTime): The earliest time (UTC) to include in the view
    # window_end (DateTime): The latest time (UTC) to include in the view
    # id (string): The Id of the calendar to view
    #              If nil, the default calendar is used
    # fields (array): An array of field names to include in results
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def get_calendar_view(token, window_start, window_end, id = nil, fields = nil, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user))

      unless id.nil?
        request_url << "/Calendars/" << id
      end

      request_url << "/CalendarView"

      request_params = {
        'startDateTime' => window_start.strftime('%Y-%m-%dT00:00:00Z'),
        'endDateTime' => window_end.strftime('%Y-%m-%dT00:00:00Z')
      }

      unless fields.nil?
        request_params['$select'] = fields.join(',')
      end

      get_view_response =make_api_call "GET", request_url, token, request_params

      JSON.parse(get_view_response)
    end

    # token (string): access token
    # payload (hash): a JSON hash representing the event entity
    # folder_id (string): The Id of the calendar folder to create the event in.
    #                     If nil, event is created in the default calendar folder.
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def create_event(token, payload, folder_id = nil, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user))

      unless folder_id.nil?
        request_url << "/Calendars/" << folder_id
      end

      request_url << "/Events"

      create_event_response = make_api_call "POST", request_url, token, nil, payload

      JSON.parse(create_event_response)
    end

    # token (string): access token
    # payload (hash): a JSON hash representing the updated event fields
    # id (string): The Id of the event to update.
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def update_event(token, payload, id, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/Events/" << id

      update_event_response = make_api_call "PATCH", request_url, token, nil, payload

      JSON.parse(update_event_response)
    end

    # token (string): access token
    # id (string): The Id of the event to delete.
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def delete_event(token, id, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/Events/" << id

      delete_response = make_api_call "DELETE", request_url, token

      return nil if delete_response.nil? || delete_response.empty?

      JSON.parse(delete_response)
    end
    #----- End Calendar API -----#

    #----- Begin Push Notification Subscription API -----#
    # token (string): access token
    # id (string): The Id of the subscription to retrieve
    # fields (array): An array of field names to include in results
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def get_subscription_by_id(token, id, fields = nil, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/subscriptions/" << id
      request_params = nil

      unless fields.nil?
        request_params = { '$select' => fields.join(',') }
      end

      get_subscription_response = make_api_call "GET", request_url, token, request_params

      JSON.parse(get_subscription_response)
    end

    # token (string): access token
    # payload (hash): a JSON hash representing the subscription entity
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def create_subscription(token, payload, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/subscriptions"

      create_subscription_response = make_api_call "POST", request_url, token, nil, payload

      JSON.parse(create_subscription_response)
    end

    # token (string): access token
    # payload (hash): a JSON hash representing the new subscription expiration date
    # id (string): The Id of the subscription to renew.
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def renew_subscription(token, payload, id, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/subscriptions/" << id

      renew_subscription_response = make_api_call "PATCH", request_url, token, nil, payload

      JSON.parse(renew_subscription_response)
    end

    # token (string): access token
    # id (string): The Id of the event to delete.
    # user (string): The user to make the call for. If nil, use the 'Me' constant.
    def delete_subscription(token, id, user = nil)
      request_url = "/api/v2.0/" << (user.nil? ? "Me" : ("users/" << user)) << "/subscriptions/" << id

      delete_response = make_api_call "DELETE", request_url, token

      return nil if delete_response.nil? || delete_response.empty?

      JSON.parse(delete_response)
    end
    #----- End Push Notification Subscription API -----#
  end
end
