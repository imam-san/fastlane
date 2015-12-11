module Spaceship
  module Tunes
    # Represents an editable version of an iTunes Connect Application
    # This can either be the live or the edit version retrieved via the app
    # rubocop:disable Metrics/ClassLength
    class AppVersion < TunesBase
      # @return (Spaceship::Tunes::Application) A reference to the application
      #   this version is for
      attr_accessor :application

      # @return (String) The version number of this version
      attr_accessor :version

      # @return (String) The copyright information of this app
      attr_accessor :copyright

      # @return (String) The appType number of this version
      attr_accessor :app_type

      # @return (Spaceship::Tunes::AppStatus) What's the current status of this app
      #   e.g. Waiting for Review, Ready for Sale, ...
      attr_reader :app_status

      # @return (Bool) Is that the version that's currently available in the App Store?
      attr_accessor :is_live

      # @return (String) App Status (e.g. 'readyForSale'). You should use `app_status` instead
      attr_accessor :raw_status

      # @return (Bool)
      attr_accessor :can_reject_version

      # @return (Bool)
      attr_accessor :can_prepare_for_upload

      # @return (Bool)
      attr_accessor :can_send_version_live

      # @return (Bool) Should the app automatically be released once it's approved?
      attr_accessor :release_on_approval

      # @return (Bool)
      attr_accessor :can_beta_test

      # @return (Bool) Does the binary contain a watch binary?
      attr_accessor :supports_apple_watch

      # @return (Spaceship::Tunes::AppImage) the structure containing information about the large app icon (1024x1024)
      attr_accessor :large_app_icon

      # @return (Spaceship::Tunes::AppImage) the structure containing information about the large watch icon (1024x1024)
      attr_accessor :watch_app_icon

      # @return (Integer) a unqiue ID for this version generated by iTunes Connect
      attr_accessor :version_id

      ####
      # GeoJson
      ####
      # @return (Spaceship::Tunes::TransitAppFile) the structure containing information about the geo json. Can be nil
      attr_accessor :transit_app_file

      ####
      # App Review Information
      ####
      # @return (String) App Review Information First Name
      attr_accessor :review_first_name

      # @return (String) App Review Information Last Name
      attr_accessor :review_last_name

      # @return (String) App Review Information Phone Number
      attr_accessor :review_phone_number

      # @return (String) App Review Information Email Address
      attr_accessor :review_email

      # @return (String) App Review Information Demo Account User Name
      attr_accessor :review_demo_user

      # @return (String) App Review Information Demo Account Password
      attr_accessor :review_demo_password

      # @return (String) App Review Information Notes
      attr_accessor :review_notes

      ####
      # Localized values
      ####

      # @return (Array) Raw access the all available languages. You shouldn't use it probably
      attr_accessor :languages

      # @return (Hash) A hash representing the keywords in all languages
      attr_reader :keywords

      # @return (Hash) A hash representing the description in all languages
      attr_reader :description

      # @return (Hash) The changelog
      attr_reader :release_notes

      # @return (Hash) A hash representing the support url in all languages
      attr_reader :support_url

      # @return (Hash) A hash representing the marketing url in all languages
      attr_reader :marketing_url

      # @return (Hash) Represents the screenshots of this app version (read-only)
      attr_reader :screenshots

      # @return (Hash) Represents the trailers of this app version (read-only)
      attr_reader :trailers

      attr_mapping({
        'appType' => :app_type,
        'canBetaTest' => :can_beta_test,
        'canPrepareForUpload' => :can_prepare_for_upload,
        'canRejectVersion' => :can_reject_version,
        'canSendVersionLive' => :can_send_version_live,
        'copyright.value' => :copyright,
        'details.value' => :languages,
        'largeAppIcon.value.originalFileName' => :app_icon_original_name,
        'largeAppIcon.value.url' => :app_icon_url,
        'releaseOnApproval.value' => :release_on_approval,
        'status' => :raw_status,
        'supportsAppleWatch' => :supports_apple_watch,
        'versionId' => :version_id,
        'version.value' => :version,

        # GeoJson
        # 'transitAppFile.value' => :transit_app_file

        # App Review Information
        'appReviewInfo.firstName.value' => :review_first_name,
        'appReviewInfo.lastName.value' => :review_last_name,
        'appReviewInfo.phoneNumber.value' => :review_phone_number,
        'appReviewInfo.emailAddress.value' => :review_email,
        'appReviewInfo.reviewNotes.value' => :review_notes,
        'appReviewInfo.userName.value' => :review_demo_user,
        'appReviewInfo.password.value' => :review_demo_password
      })

      class << self
        # Create a new object based on a hash.
        # This is used to create a new object based on the server response.
        def factory(attrs)
          obj = self.new(attrs)
          obj.unfold_languages

          return obj
        end

        # @param application (Spaceship::Tunes::Application) The app this version is for
        # @param app_id (String) The unique Apple ID of this app
        # @param is_live (Boolean)
        def find(application, app_id, is_live)
          attrs = client.app_version(app_id, is_live)
          return nil unless attrs
          attrs.merge!(application: application)
          attrs.merge!(is_live: is_live)

          return self.factory(attrs)
        end
      end

      # @return (Bool) Is that version currently available in the App Store?
      # rubocop:disable Style/PredicateName
      def is_live?
        is_live
      end
      # rubocop:enable Style/PredicateName

      # Call this method to make sure the given languages are available for this app
      # You should call this method before accessing the name, description and other localized values
      # This will create the new language if it's not available yet and do nothing if everything's there
      # Important: Due to a bug you have to fetch the `edit_version` again, as it doesn't get refreshed immediately
      def create_languages(languages)
        languages = [languages] if languages.kind_of?(String)
        raise "Please pass an array" unless languages.kind_of? Array

        copy_from = self.languages.find { |a| a['language'] == 'en-US' } || self.languages.first

        languages.each do |language|
          # First, see if it's already available
          found = self.languages.find do |local|
            local['language'] == language
          end
          next if found

          new_language = copy_from.clone
          new_language['language'] = language

          self.languages << new_language
        end
        nil
      end

      # Returns an array of all builds that can be sent to review
      def candidate_builds
        res = client.candidate_builds(self.application.apple_id, self.version_id)
        builds = []
        res.each do |attrs|
          next unless attrs["type"] == "BUILD" # I don't know if it can be something else.
          builds << Tunes::Build.factory(attrs)
        end
        return builds
      end

      # Select a build to be submitted for Review.
      # You have to pass a build you got from - candidate_builds
      # Don't forget to call save! after calling this method
      def select_build(build)
        raw_data.set(['preReleaseBuildVersionString', 'value'], build.build_version)
        raw_data.set(['preReleaseBuildTrainVersionString'], build.train_version)
        raw_data.set(['preReleaseBuildUploadDate'], build.upload_date)
        true
      end

      # Set the age restriction rating
      # Call it like this:
      # v.update_rating({
      #   'CARTOON_FANTASY_VIOLENCE' => 0,
      #   'MATURE_SUGGESTIVE' => 2,
      #   'UNRESTRICTED_WEB_ACCESS' => 0,
      #   'GAMBLING_CONTESTS' => 0
      # })
      #
      # Available Values
      # https://github.com/KrauseFx/deliver/blob/master/Reference.md
      def update_rating(hash)
        raise "Must be a hash" unless hash.kind_of?(Hash)

        hash.each do |key, value|
          to_edit = self.raw_data['ratings']['nonBooleanDescriptors'].find do |current|
            current['name'].include?(key)
          end

          if to_edit
            to_set = "NONE" if value == 0
            to_set = "INFREQUENT_MILD" if value == 1
            to_set = "FREQUENT_INTENSE" if value == 2
            raise "Invalid value '#{value}' for '#{key}', must be 0-2" unless to_set
            to_edit['level'] = "ITC.apps.ratings.level.#{to_set}"
          else
            # Maybe it's a boolean descriptor?
            to_edit = self.raw_data['ratings']['booleanDescriptors'].find do |current|
              current['name'].include?(key)
            end

            if to_edit
              to_set = "NO"
              to_set = "YES" if value.to_i > 0
              to_edit['level'] = "ITC.apps.ratings.level.#{to_set}"
            else
              raise "Could not find option '#{key}' in the list of available options"
            end
          end
        end
        true
      end

      # Push all changes that were made back to iTunes Connect
      def save!
        client.update_app_version!(application.apple_id, self.version_id, raw_data)
      end

      # @return (String) An URL to this specific resource. You can enter this URL into your browser
      def url
        url = "https://itunesconnect.apple.com/WebObjects/iTunesConnect.woa/ra/ng/app/904332168/ios/versioninfo/"
        url += "deliverable" if self.is_live?
        return url
      end

      # Private methods
      def setup
        # Properly parse the AppStatus
        status = raw_data['status']
        @app_status = Tunes::AppStatus.get_from_string(status)
        setup_large_app_icon
        setup_watch_app_icon
        setup_transit_app_file if supports_app_transit?
        setup_screenshots
        setup_trailers
      end

      # Uploads or removes the large icon
      # @param icon_path (String): The path to the icon. Use nil to remove it
      def upload_large_icon!(icon_path)
        unless icon_path
          @large_app_icon.reset!
          return
        end
        upload_image = UploadFile.from_path icon_path
        image_data = client.upload_large_icon(self, upload_image)

        @large_app_icon.reset!({ asset_token: image_data['token'], original_file_name: upload_image.file_name })
      end

      # Uploads or removes the watch icon
      # @param icon_path (String): The path to the icon. Use nil to remove it
      def upload_watch_icon!(icon_path)
        unless icon_path
          @watch_app_icon.reset!
          return
        end
        upload_image = UploadFile.from_path icon_path
        image_data = client.upload_watch_icon(self, upload_image)

        @watch_app_icon.reset!({ asset_token: image_data["token"], original_file_name: upload_image.file_name })
      end

      # Uploads or removes the transit app file
      # @param icon_path (String): The path to the geojson file. Use nil to remove it
      def upload_geojson!(geojson_path)
        unless geojson_path
          raw_data["transitAppFile"]["value"] = nil
          @transit_app_file = nil
          return
        end
        upload_file = UploadFile.from_path geojson_path
        geojson_data = client.upload_geojson(self, upload_file)

        @transit_app_file = Tunes::TransitAppFile.factory({}) if @transit_app_file.nil?
        @transit_app_file .url = nil # response.headers['Location']
        @transit_app_file.asset_token = geojson_data["token"]
        @transit_app_file.name = upload_file.file_name
        @transit_app_file.time_stamp = Time.now.to_i * 1000 # works without but...
      end

      # Uploads or removes a screenshot
      # @param icon_path (String): The path to the screenshot. Use nil to remove it
      # @param sort_order (Fixnum): The sort_order, from 1 to 5
      # @param language (String): The language for this screenshot
      # @param device (string): The device for this screenshot
      def upload_screenshot!(screenshot_path, sort_order, language, device)
        raise "sort_order must be positive" unless sort_order > 0
        raise "sort_order must not be > 5" if sort_order > 5
        # this will also check both language and device parameters
        device_lang_screenshots = screenshots_data_for_language_and_device(language, device)["value"]
        existing_sort_orders = device_lang_screenshots.map { |s| s["value"]["sortOrder"] }
        if screenshot_path # adding / replacing
          upload_file = UploadFile.from_path screenshot_path
          screenshot_data = client.upload_screenshot(self, upload_file, device)

          new_screenshot = {
              "value" => {
                  "assetToken" => screenshot_data["token"],
                  "sortOrder" => sort_order,
                  "url" => nil,
                  "thumbNailUrl" => nil,
                  "originalFileName" => upload_file.file_name
              }
          }
          if existing_sort_orders.include?(sort_order) # replace
            device_lang_screenshots[existing_sort_orders.index(sort_order)] = new_screenshot
          else # add
            device_lang_screenshots << new_screenshot
          end
        else # removing
          raise "cannot remove screenshot with non existing sort_order" unless existing_sort_orders.include?(sort_order)
          device_lang_screenshots.delete_at(existing_sort_orders.index(sort_order))
        end
        setup_screenshots
      end

      # Uploads, removes a trailer video or change its preview image
      #
      # A preview image for the video is required by ITC and is usually automatically extracted by your browser.
      # This method will either automatically extract it from the video (using `ffmpeg) or allow you
      # to specify it using +preview_image_path+.
      # If the preview image is specified, ffmpeg` will ot be used. The image resolution will be checked against
      # expectations (which might be different from the trailer resolution.
      #
      # It is recommended to extract the preview image using the spaceship related tools in order to ensure
      # the appropriate format and resolution are used.
      #
      # Note: if the video is already set, the +trailer_path+ is only used to grab the preview screenshot.
      # Note: to extract its resolution and a screenshot preview, the `ffmpeg` tool will be used
      #
      # @param icon_path (String): The path to the screenshot. Use nil to remove it
      # @param sort_order (Fixnum): The sort_order, from 1 to 5
      # @param language (String): The language for this screenshot
      # @param device (String): The device for this screenshot
      # @param timestamp (String): The optional timestamp of the screenshot to grab
      def upload_trailer!(trailer_path, language, device, timestamp = "05.00", preview_image_path = nil)
        raise "No app trailer supported for iphone35" if device == 'iphone35'

        device_lang_trailer = trailer_data_for_language_and_device(language, device)
        if trailer_path # adding / replacing trailer / replacing preview
          raise "Invalid timestamp #{timestamp}" if (timestamp =~ /^[0-9][0-9].[0-9][0-9]$/).nil?

          if preview_image_path
            check_preview_screenshot_resolution(preview_image_path, device)
            video_preview_path = preview_image_path
          else
            # IDEA: optimization, we could avoid fetching the screenshot if the timestamp hasn't changed
            video_preview_resolution = video_preview_resolution_for(device, trailer_path)
            video_preview_path = Utilities.grab_video_preview(trailer_path, timestamp, video_preview_resolution)
          end
          video_preview_file = UploadFile.from_path video_preview_path
          video_preview_data = client.upload_trailer_preview(self, video_preview_file)

          trailer = device_lang_trailer["value"]
          if trailer.nil? # add trailer
            upload_file = UploadFile.from_path trailer_path
            trailer_data = client.upload_trailer(self, upload_file)
            trailer_data = trailer_data['responses'][0]
            trailer = {
                "videoAssetToken" => trailer_data["token"],
                "descriptionXML" => trailer_data["descriptionDoc"],
                "contentType" => upload_file.content_type
            }
            device_lang_trailer["value"] = trailer
          end
          # add / update preview
          # different format required
          ts = "00:00:#{timestamp}"
          ts[8] = ':'

          trailer.merge!({
            "pictureAssetToken" => video_preview_data["token"],
            "previewFrameTimeCode" => "#{ts}",
            "isPortrait" => Utilities.portrait?(video_preview_path)
          })
        else # removing trailer
          raise "cannot remove non existing trailer" if device_lang_trailer["value"].nil?
          device_lang_trailer["value"] = nil
        end
        setup_trailers
      end

      # Prefill name, keywords, etc...
      def unfold_languages
        {
          keywords: :keywords,
          description: :description,
          supportURL: :support_url,
          marketingURL: :marketing_url,
          releaseNotes: :release_notes
        }.each do |json, attribute|
          instance_variable_set("@#{attribute}".to_sym, LanguageItem.new(json, languages))
        end
      end

      # These methods takes care of properly parsing values that
      # are not returned in the right format, e.g. boolean as string
      def release_on_approval
        super == 'true'
      end

      def supports_apple_watch
        !super.nil?
      end

      private

      def setup_large_app_icon
        large_app_icon = raw_data["largeAppIcon"]["value"]
        @large_app_icon = nil
        @large_app_icon = Tunes::AppImage.factory(large_app_icon) if large_app_icon
      end

      def setup_watch_app_icon
        watch_app_icon = raw_data["watchAppIcon"]["value"]
        @watch_app_icon = nil
        @watch_app_icon = Tunes::AppImage.factory(watch_app_icon) if watch_app_icon
      end

      def supports_app_transit?
        raw_data["transitAppFile"] != nil
      end

      def setup_transit_app_file
        transit_app_file = raw_data["transitAppFile"]["value"]
        @transit_app_file = nil
        @transit_app_file = Tunes::TransitAppFile.factory(transit_app_file) if transit_app_file
      end

      def screenshots_data_for_language_and_device(language, device)
        container_data_for_language_and_device("screenshots", language, device)
      end

      def trailer_data_for_language_and_device(language, device)
        container_data_for_language_and_device("appTrailers", language, device)
      end

      def container_data_for_language_and_device(data_field, language, device)
        raise "#{device} isn't a valid device name" unless DeviceType.exists?(device)

        languages = raw_data_details.select { |d| d["language"] == language }
        # IDEA: better error for non existing language
        raise "#{language} isn't an activated language" unless languages.count > 0
        lang_details = languages[0]
        devices_details = lang_details[data_field]["value"]
        raise "Unexpected state: missing device details for #{device}" unless devices_details.key? device
        devices_details[device]
      end

      def setup_screenshots
        @screenshots = {}
        raw_data_details.each do |row|
          # Now that's one language right here
          @screenshots[row['language']] = setup_screenshots_for(row)
        end
      end

      # generates the nested data structure to represent screenshots
      def setup_screenshots_for(row)
        screenshots = row.fetch("screenshots", {}).fetch("value", nil)
        return [] unless screenshots

        result = []

        screenshots.each do |device_type, value|
          value["value"].each do |screenshot|
            screenshot_data = screenshot["value"]
            data = {
                device_type: device_type,
                language: row["language"]
            }.merge(screenshot_data)
            result << Tunes::AppScreenshot.factory(data)
          end
        end

        return result
      end

      def setup_trailers
        @trailers = {}
        raw_data_details.each do |row|
          # Now that's one language right here
          @trailers[row["language"]] = setup_trailers_for(row)
        end
      end

      # generates the nested data structure to represent trailers
      def setup_trailers_for(row)
        trailers = row.fetch("appTrailers", {}).fetch("value", nil)
        return [] unless trailers

        result = []

        trailers.each do |device_type, value|
          trailer_data = value["value"]
          next if trailer_data.nil?
          data = {
              device_type: device_type,
              language: row["language"]
          }.merge(trailer_data)
          result << Tunes::AppTrailer.factory(data)
        end

        return result
      end

      # identify the required resolution for this particular video screenshot
      def video_preview_resolution_for(device, video_path)
        is_portrait = Utilities.portrait?(video_path)
        TunesClient.video_preview_resolution_for(device, is_portrait)
      end

      # ensure the specified preview screenshot has the expected resolution the specified target +device+
      def check_preview_screenshot_resolution(preview_screenshot_path, device)
        is_portrait = Utilities.portrait?(preview_screenshot_path)
        expected_resolution = TunesClient.video_preview_resolution_for(device, is_portrait)
        actual_resolution = Utilities.resolution(preview_screenshot_path)
        orientation = is_portrait ? "portrait" : "landscape"
        raise "Invalid #{orientation} screenshot resolution for device #{device}. Should be #{expected_resolution}" unless actual_resolution == expected_resolution
      end

      def raw_data_details
        raw_data["details"]["value"]
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
