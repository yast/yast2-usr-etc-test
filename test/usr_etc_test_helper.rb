# Copyright (c) [2017] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.
#
#
# Checking *-filelists.xml.gz for /usr/etc entries which are currently not
# handled by YAST correctly.
#
require 'rspec'
require 'yaml'
require 'tmpdir'
require 'zlib'
require 'rexml/document'
require 'rexml/streamlistener'

# use the XML SAX (streaming) parser,
# the uncompressed Leap 15.1 XML is ~97MB!
class Listener
  include REXML::StreamListener

  attr_reader :files

  def initialize
    @files = []
  end

  def tag_start(tag, _attrs)
    @in_file_tag = true if tag == 'file'
  end

  def text(data)
    @file = data if @in_file_tag
  end

  def tag_end(tag)
    if tag == 'file'
      files << @file if @file.start_with?('/usr/etc/')
      @in_file_tag = false
    end
  end
end

class UsrEtcTestHelper
  TEST_DIR = __dir__
  REPOSITORIES_CONF = File.join(TEST_DIR, 'repos_conf.yml')
  TEMPORARY_DIRECTORY = 'etc_ust_tmp'.freeze
  WHITELIST = 'white-list.yml'.freeze

  attr_reader :distribution, :white_list, :tmp_dir

  # New constructor for UsrEtcTestHelper class
  #
  # @param [String] directory name containing e.g. the regarding whitelist,...
  #        (e.g., "Factory",... )
  def initialize(distribution)
    @distribution = distribution
  end

  def check_user_etc
    prepare_distribution
    files = []

    Dir[File.join(@tmp_dir, '/**/*-filelists.xml.gz')].each do |f|
      files.concat(files_from_xml(f))
    end
    files.uniq!
    files.sort!
    puts 'following files have to be checked:'
    puts files
    puts "Found #{files.size} files"
    puts 'comparing with the white list....'
    files.delete_if do |file|
      ret = false
      @white_list.each do |entry|
        entry['files'].each do |tag|
          next unless file == tag
          puts "File #{file} from package #{entry['defined_by']} has already" \
               " been checked (#{entry['yast_support'].join(', ')})"
          ret = true
        end
      end
      ret
    end

    cleanup
    files
  end

  private

  def files_from_xml(file)
    puts "Processing #{file}...This could take some minutes...."

    l = Listener.new

    Zlib::GzipReader.open(file) do |gz|
      REXML::Document.parse_stream(gz, l)
    end

    l.files
  end

  # Removes a temporary directory for the current object
  def cleanup
    return unless @tmp_dir && File.exist?(@tmp_dir)

    puts "Removing temporary directory #{@tmp_dir}"
    FileUtils.rm_rf @tmp_dir
  end

  # Prepares a testing environment for a given repositories
  # Directories are named after products and there is a corresponding
  # configuration in #{REPOSITORIES_CONF} file.
  def prepare_distribution
    repo_config = YAML.load_file(REPOSITORIES_CONF)

    unless repo_config.key?(@distribution)
      raise "Cannot find configuration in repo_conf.yml for #{@distribution}"
    end

    distribution_config = repo_config[@distribution]
    unless distribution_config['repository']
      raise "Cannot find 'repository' in configuration for '#{@distribution}'"
    end

    @white_list = YAML.load_file(File.join(TEST_DIR, @distribution, WHITELIST))
    puts "white list: #{@white_list}"

    @tmp_dir = Dir.mktmpdir "#{TEMPORARY_DIRECTORY}_#{@distribution}_"
    puts "Test for #{@distribution} will use temporary dir #{@tmp_dir}"

    puts 'Downloading *-filelists.xml.gz from repo ' \
      "#{distribution_config['repository']}"
    command = "cd #{@tmp_dir} ; " \
      "/usr/bin/wget -r -nd --no-parent -A '*-filelists.xml.gz' " \
      "#{distribution_config['repository']} ; cd -"

    puts "With command #{command}"
    ret = system(command)
    raise 'Cannot fetch filelists.xml.gz from distribution' unless ret
  end
end
