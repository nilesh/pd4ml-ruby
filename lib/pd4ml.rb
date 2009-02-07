require "tempfile"
require 'logger'

# Exception class representing an internal error in the HTMLDoc
# class.
class PD4MLException < StandardError; end

# The wrapper class around HTMLDOC, providing methods for setting
# the options for the application and retriving the generate output
# either as a file, diretory or string.
class PD4ML

  VERSION = "0.1.0"

  PAGE_DIMENSIONS = %w(A1 A2 A3 A4 A5 A6 A7 A8 A9 A10 HALFLETTER ISOB0 
                       ISOB1 ISOB2 ISOB3 ISOB4 ISOB5 LEDGER LEGAL LETTER 
                       NOTE TABLOID)

  PAGE_ORIENTATIONS = %w(PORTRAIT LANDSCAPE)
  
  BOOKMARK_ELEMENTS = %w(HEADINGS ANCHORS)

  # Set the default paths for the required files
  @@java_path ||= "java"
  @@jar_path  ||= "#{Rails.root}/extras/pd4ml/pd4ml.jar"
  @@font_path ||= "#{Rails.root}/extras/fonts"

  # Set the default options
  @@default_options ||= {
    :html_width                 => 800,
    :page_dimension             => 'A4',
    :page_orientation           => 'PORTRAIT',
    :inset_unit                 => 'mm',
    :inset_left                 => 20,
    :inset_top                  => 10,
    :inset_right                => 10,
    :inset_bottom               => 10,
    :bookmark_elements          => 'HEADINGS',
    :allow_annotate             => true, 
    :allow_copy                 => true, 
    :allow_modify               => true, 
    :allow_print                => true,
    :debug                      => false,
    :header => {
      :area_height                => -1,
      :color                      => '#000000',
      :font                       => 'Helvetica',
      :font_size                  => '12',
      :html_template              => '${title}',
      :initial_page_number        => 1,
      :page_background_color      => nil,
      :page_background_image_url  => nil,
      :page_number_alignment      => nil,
      :page_number_template       => nil,
      :pages_to_skip              => nil,
      :title_alignment            => nil,
      :title_template             => nil,
      :watermark                  => nil
    },
    :footer => {
      :area_height                => -1,
      :color                      => '#000000',
      :font                       => 'Helvetica',
      :font_size                  => '12',
      :html_template              => '${page} of ${pages}',
      :initial_page_number        => 1,
      :page_background_color      => nil,
      :page_background_image_url  => nil,
      :page_number_alignment      => nil,
      :page_number_template       => nil,
      :pages_to_skip              => nil,
      :title_alignment            => nil,
      :title_template             => nil,
      :watermark                  => nil
    }
  }

  attr_writer :user_password

  # Creates a blank PD4ML wrapper, using <tt>format</tt> to
  # indicate whether the output will be HTML, PDF or PS. The format
  # defaults to PDF, and can change using one of the module
  # contants.
  def initialize(options={})
    @options = @@default_options.merge(options)
    @content = ""
    @command_options = ""
    @user_password = nil
    @tempfiles = []
  end

  # Creates a blank PD4ML wrapper and passes it to a block. When
  # the block finishes running, the <tt>generate</tt> method is
  # automatically called. The result of <tt>generate</tt> is then
  # passed back to the application.
  def self.create(options={}, &block)
    pdf = PD4ML.new(options)
    if block_given?
      yield pdf
      pdf.generate
    end
  end
  
  # Creates a blank PD4ML wrapper and passes it to a block. When
  # the block finishes running, the <tt>generate</tt> method is
  # automatically called. The result of <tt>generate</tt> is then
  # stored at the specified file path.
  def self.create_and_save(file_path, options={}, &block)
    pdf = PD4ML.new(options)
    if block_given?
      yield pdf
      pdf.save_to(file_path)
    end
  end
  
  # Save the PDF::PD4ML object to a PDF file.
  def save_to(file_path)
    File.open(file_path, 'w') {|f| f.write(self.generate) }
  end

  # Define methods to get and set the java_path, jar_path and the 
  # font_path global variables
  %w(jar_path java_path font_path).each do |attr|
    eval <<-METHOD
      def self.#{attr}
        @@#{attr}
      end
      def self.#{attr}=(value)
        @@#{attr} = value
        #{"self.build_font_information" if attr == 'font_path'}
      end
    METHOD
  end

  # Sets an option for the wrapper. Only valid PD4ML options will
  # be accepted. The name of the option is a symbol, but the value
  # can be anything. Invalid options will throw an exception. To
  # unset an option, use <tt>nil</tt> as the value. Options with
  # negated counterparts, like <tt>:encryption</tt>, can be set
  # using :no or :none as the value.
  def set_option(option, value)
    if @@default_options.keys.include?(option)
      if value_valid_for_option?(option, value)
        @options[option] = value
      end
    else
      raise PD4MLException.new("Invalid option #{option.to_s}")
    end
  end

  def add_content(html_content)
    @content << html_content
  end

  alias_method :<<, :add_content

  # Invokes PD4ML and generates the output. If an output directory
  # or file is provided, the method will return <tt>true</tt> or
  # <tt>false</tt> to indicate completion. If no output directory or
  # file is provided, it will return a string representing the
  # entire output. Generate will raise a PDF::PD4MLException if
  # the program path can't be found.
  def generate
    # Check if required files are present
    raise PD4MLException.new("Invalid jar path: #{@@jar_path}") unless File.exists? @@jar_path
    raise PD4MLException.new("Invalid java path: #{@@java_path}") unless File.exists? @@java_path
    raise PD4MLException.new("Invalid font path: #{@@font_path}") unless File.exists? @@font_path
    
    # Execute
    logger.info "[PD4ML] command: #{pd4ml_command}" if @options[:debug]
    result = IO.popen(pd4ml_command) { |s| s.read }

    # Check whether the program really was executed
    if $?.exitstatus == 127
      raise PD4MLException.new("Sorry. Could not run PD4ML. Giving up!")
    else
      return result
    end

  ensure
    @tempfiles.each { |t| t.close }
  end
  
  
  # Builds the pd4fonts.properties file in the fonts directory.
  # This file is required for PD4ml to identify font names.
  def self.build_font_information
    raise PD4MLException.new("Invalid font path: #{@@font_path}") unless File.exists? @@font_path
    
    # Font build comand
    font_command = "#{@@java_path} -Xmx512m -Djava.awt.headless=true -jar \"#{@@jar_path}\" -configure.fonts \"#{@@font_path}\" 2>&1"
    
    # Execute
    result = IO.popen(font_command) { |s| s.read }

    # Check whether the program really was executed
    if $?.exitstatus == 127
      raise PD4MLException.new("Sorry. Could not build font properties file. Giving up!")
    else
      return result
    end
  end
  
  
private  
  
  # Create a temp file from the content and return the path to the
  # temp file
  def input_file
    t = Tempfile.new("pd4ml.html", "#{Rails.root}/tmp")
    t.binmode
    t.write(@content)
    t.flush
    @tempfiles << t
    t.path
  end
  
  # Build the PD4ML command
  def pd4ml_command
    class_path = "#{@@jar_path}:.:#{File.dirname(__FILE__)}"
    class_path = "\"#{@@jar_path}\";\"#{File.dirname(__FILE__)}\"" if RUBY_PLATFORM =~ /mswin/
    "#{@@java_path} -Xmx512m -Djava.awt.headless=true -cp #{class_path} Pd4Ruby #{command_parameters} 2>&1"
  end

  # Build the PD4ML command parameters
  def command_parameters
    command_options = ""
    
    command_options << "--file \"#{input_file}\" "
    command_options << "--width #{@options[:html_width]} "
    command_options << "--pagesize #{@options[:page_dimension]} "
    command_options << "--orientation #{@options[:page_orientation]} "
    command_options << "--permissions #{pdf_permissions} "
    command_options << "--password #{@user_password} " unless @user_password.blank?
    command_options << "--insets #{page_insets} "
    command_options << "--bookmarks #{@options[:bookmark_elements]} "
    command_options << "--ttf \"#{@@font_path}\" "
    
    command_options << header_options unless header_options.blank?
    command_options << footer_options unless footer_options.blank?
    
    command_options << "--debug " if @options[:debug]
    
    command_options  
  end
    
  # Builds permissions for the PDF encryption
  # The permission flags are 65472 (decimal) or
  # 1111111111000000 (binary).  Bits 0 and 1 are reserved (always 0), bit
  # 2 is the print permission (0 here, meaning that printing is not
  # allowed), and bits 3, 4, and 5, are the "modify", "copy text", and
  # "add/edit annotations" permissions (all disallowed in this example).
  # The higher bits are reserved.
  def pdf_permissions
    annotate  = @options[:allow_annotate] ? 1 : 0
    print     = @options[:allow_print]    ? 1 : 0
    copy      = @options[:allow_copy]     ? 1 : 0
    modify    = @options[:allow_modify]   ? 1 : 0
    permissions = "1111111111#{annotate}#{copy}#{modify}#{print}00".to_i(2)
    logger.info "[PD4ML] permissions: #{permissions.to_s(2)}" if @options[:debug]
    permissions
  end
  
  # Builds the page insets string to be passed to the JAR file
  def page_insets
    "#{@options[:inset_top]},#{@options[:inset_left]},#{@options[:inset_bottom]},#{@options[:inset_right]},#{@options[:inset_unit]}"
  end
  
  # Return true if the given value for the option is valid
  def value_valid_for_option?(option, value)
    case option
      
    when :html_width          then value.is_a? Fixnum
    when :page_dimension      then PAGE_DIMENSIONS.include? value
    when :page_orientation    then PAGE_ORIENTATIONS.include? value 
    when :inset_unit          then %(mm pt).include? value
    when :inset_left          then value.is_a? Fixnum
    when :inset_top           then value.is_a? Fixnum
    when :inset_right         then value.is_a? Fixnum
    when :inset_bottom        then value.is_a? Fixnum
    when :bookmark_elements   then BOOKMARK_ELEMENTS.include? value
    when :allow_annotate      then [true, false].include? value 
    when :allow_copy          then [true, false].include? value 
    when :allow_modify        then [true, false].include? value 
    when :allow_print         then [true, false].include? value 
    when :debug               then [true, false].include? value  
    end
  end
  
  def header_options
    return if @options[:header].blank?
    head_options = "--header '"
    @options[:header].each do |key, value|
      unless value.blank?
        head_options << ""
      end
    end
    head_options << "' "
  end
  
  def footer_options
    return if @options[:footer].blank?
    foot_options = "--footer '"
    @options[:footer].each do |key, value|
      unless value.blank?
        foot_options << ""
      end
    end
    foot_options << "' "
  end
  
  # Use Rails' default logger for debug commands
  def logger
    RAILS_DEFAULT_LOGGER
  end

end
