require 'fileutils'

# Create the directories if they don't exist
FileUtils.mkdir_p File.join(File.dirname(__FILE__), '..', '..', 'extras', 'pd4ml')
FileUtils.mkdir_p File.join(File.dirname(__FILE__), '..', '..', 'extras', 'fonts')