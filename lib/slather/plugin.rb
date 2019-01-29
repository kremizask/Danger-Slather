module Danger
  # Show code coverage of the project and by file. Add warnings or fail the
  # Build if a minimum coverage are not achieved. It uses Slather Framework for
  # calculate coverage, so it's required to configurate the slather object
  # before using it.
  #
  # @example Require a minimum file coverage of 30%, a project coverage of 60% and show all modified files coverage
  #       slather.configure("Path/to/my/project.xcodeproj", "MyScheme")
  #       slather.notify_if_coverage_is_less_than(minimum_coverage: 60)
  #       slather.notify_if_modified_file_is_less_than(minimum_coverage: 30)
  #       slather.notify_if_new_file_is_less_than(minimum_coverage: 70)
  #       slather.show_coverage
  #
  # @see  BrunoMazzo/danger-slather
  # @tags slather, code coverage, xcode, iOS
  class DangerSlather < Plugin
    # Required method to configure slather. It's required at least the path
    # to the project and the scheme used with code coverage enabled
    # @return  [void]
    def configure(xcodeproj_path, scheme, options: {})
      require 'slather'
      @project = Slather::Project.open(xcodeproj_path)
      @project.scheme = scheme
      @project.workspace = options[:workspace]
      @project.build_directory = options[:build_directory]
      @project.ignore_list = options[:ignore_list]
      @project.ci_service = options[:ci_service]
      @project.coverage_access_token = options[:coverage_access_token]
      @project.coverage_service = options[:coverage_service] || :terminal
      @project.source_directory = options[:source_directory]
      @project.output_directory = options[:output_directory]
      @project.input_format = options[:input_format]
      @project.binary_file = options[:binary_file]
      @project.decimals = options[:decimals]
      @project.configure
      @project.post if options[:post]
    end

    # Total coverage of the project
    # @return   [Float]
    def total_coverage
      unless @project.nil?
        @total_coverage ||= begin
          total_project_lines = 0
          total_project_lines_tested = 0
          @project.coverage_files.each do |coverage_file|
            total_project_lines_tested += coverage_file.num_lines_tested
            total_project_lines += coverage_file.num_lines_testable
          end
          @total_coverage = (total_project_lines_tested / total_project_lines.to_f) * 100.0
        end
      end
    end

    # Method to check if the coverage of the project is at least a minumum
    # @param options [Hash] a hash with the options
    # @option options [Float] :minimum_coverage the minimum code coverage required
    # @option options [Symbol] :notify_level the level of notification
    # @return [Array<String>]
    def notify_if_coverage_is_less_than(options)
      minimum_coverage = options[:minimum_coverage]
      notify_level = options[:notify_level] || :fail
      if total_coverage < minimum_coverage
        notify_message = "Total coverage less than #{minimum_coverage}%"
        if notify_level == :fail
          fail notify_message
        else
          warn notify_message
        end
      end
    end

    # Method to check if the coverage of modified files is increaded by given percent at least a minumum
    # @param options [Hash] a hash with the options
    # @option options [Float] :minimum_coverage the minimum code coverage required for a file
    # @option options [Symbol] :notify_level the level of notification
    # @return [Array<String>]
    def notify_if_modified_file_is_less_than(options)
      minimum_coverage = options[:minimum_coverage]
      notify_level = options[:notify_level] || :fail

      if all_modified_files_coverage.count > 0
        files_to_notify = all_modified_files_coverage.select do |file|
          file.percentage_lines_tested < minimum_coverage
        end
        notify_messages = files_to_notify.map do |file|
          "#{file.source_file_pathname_relative_to_repo_root} has less than #{minimum_coverage}% code coverage"
        end

        notify_messages.each do |message|
          if notify_level == :fail
            fail message
          else
            warn message
          end
        end
      end
    end

    # Method to check if the coverage of added files is at least a minumum
    # @param options [Hash] a hash with the options
    # @option options [Float] :minimum_coverage the minimum code coverage required for a file
    # @option options [Symbol] :notify_level the level of notification
    # @return [Array<String>]
    def notify_if_new_file_is_less_than(options)
      minimum_coverage = options[:minimum_coverage]
      notify_level = options[:notify_level] || :fail

      if all_modified_files_coverage.count > 0
        files_to_notify = all_modified_files_coverage.select do |file|
          file.percentage_lines_tested < minimum_coverage
        end
        notify_messages = files_to_notify.map do |file|
          "#{file.source_file_pathname_relative_to_repo_root} has less than #{minimum_coverage}% code coverage"
        end

        notify_messages.each do |message|
          if notify_level == :fail
            fail message
          else
            warn message
          end
        end
      end
    end

    # String header with the total coverage of the project
    # @return [String]
    def total_coverage_markdown
      unless @project.nil?
        "### Total coverage: **`#{@project.decimal_f([total_coverage])}%`**\n"
      end
    end

    # Show a header with the total coverage of the project
    # @return [Array<String>]
    def show_total_coverage
      unless @project.nil?
        markdown total_coverage_markdown
      end
    end

    # Build a coverage markdown table of the changed files coverage
    # @return [String]
    def changed_files_coverage_table
      unless @project.nil?
        line = ''
        if all_changed_files_coverage.count > 0
          line << "File | Coverage\n"
          line << "-----|-----\n"
          all_changed_files_coverage.each do |coverage_file|
            file_name = coverage_file.source_file_pathname_relative_to_repo_root.to_s
            percentage = @project.decimal_f([coverage_file.percentage_lines_tested])
            line << "#{file_name} | **`#{percentage}%`**\n"
          end
        end
        return line
      end
    end

    # Show the table build by changed_files_coverage_table
    # @return [Array<String>]
    def show_changed_files_coverage
      unless @project.nil?
        markdown changed_files_coverage_table
      end
    end

    # Show a header with the total coverage and coverage table
    # @return [Array<String>]
    def show_coverage
      unless @project.nil?
        line = "## Code coverage\n"
        line << total_coverage_markdown
        line << changed_files_coverage_table
        line << '> Powered by [Slather](https://github.com/SlatherOrg/slather)'
        markdown line
      end
    end

    # Array of files that we have coverage information and was modified or added
    # @return [Array<File>]
    def all_changed_files_coverage
      unless @project.nil?
        all_changed_files_coverage ||= begin
          modified_files = git.modified_files.nil? ? [] : git.modified_files
          added_files = git.added_files.nil? ? [] : git.added_files
          all_changed_files = modified_files | added_files
          @project.coverage_files.select do |file|
            all_changed_files.include? file.source_file_pathname_relative_to_repo_root.to_s
          end
        end

        all_changed_files_coverage
      end
    end

    # Array of files that we have coverage information and was modified
    # @return [Array<File>]
    def all_modified_files_coverage
      unless @project.nil?
        all_modified_files_coverage ||= begin
          modified_files = git.modified_files.nil? ? [] : git.modified_files
          @project.coverage_files.select do |file|
            modified_files.include? file.source_file_pathname_relative_to_repo_root.to_s
          end
        end

        all_modified_files_coverage
      end
    end

    # Array of added files that we have coverage information
    # @return [Array<File>]
    def all_added_files_coverage
      unless @project.nil?
        all_added_files_coverage ||= begin
          added_files = git.added_files.nil? ? [] : git.added_files
          @project.coverage_files.select do |file|
            added_files.include? file.source_file_pathname_relative_to_repo_root.to_s
          end
        end

        all_added_files_coverage
      end
    end

    private :all_modified_files_coverage, all_changed_files_coverage, all_added_files_coverage, :total_coverage_markdown
  end
end
