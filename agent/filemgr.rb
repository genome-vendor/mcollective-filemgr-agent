require 'fileutils'
require 'digest/md5'

module MCollective
  module Agent
    # A basic file management agent, you can touch, remove or inspec files.
    #
    # A common use case for this plugin is to test your mcollective setup
    # as such if you just call the touch/info/remove actions with no arguments
    # it will default to the file /var/run/mcollective.plugin.filemgr.touch
    # or whatever is specified in the plugin.filemgr.touch_file setting
    class Filemgr<RPC::Agent
      action "touch" do
        touch
      end

      # Basic file removal action
      action "remove" do
        remove
      end

      # Basic status of a file
      action "status" do
        status
      end

      # Find files in provided directory. Optionally recurse through subdirectories
      # or limit results by file mtime.
      action "find" do
        base_dir = request.data[:directory]
        age_minutes = request.data[:age_minutes]
        age_hours = request.data[:age_hours]
        age_days = request.data[:age_days]
        recurse = request.data[:recurse]

        age = nil
        if !age_minutes.nil?
          age = Time.now - (60 * age_minutes)
        elsif !age_hours.nil?
          age = Time.now - (60 * 60 * age_hours)
        elsif !age_days.nil?
          age = Time.now - (60 * 60 * 24 * age_days)
        end

        files = Array.new
        Find.find(base_dir) do |path|
          if FileTest.directory?(path)
            if recurse or path == base_dir
              next
            else
              Find.prune
            end
          elsif FileTest.file?(path)
            if !age.nil?
              mtime = File.mtime(path)
              if (mtime <=> age) == -1
                files.push(path)
              else
                next
              end
            else
              files.push(path)
            end
          end
        end
        reply[:file] = files
      end

      def get_filename
        request[:file] || config.pluginconf["filemgr.touch_file"] || "/var/run/mcollective.plugin.filemgr.touch"
      end

      def status
        file = get_filename
        reply[:name] = file
        reply[:output] = "not present"
        reply[:type] = "unknown"
        reply[:mode] = "0000"
        reply[:present] = 0
        reply[:size] = 0
        reply[:mtime] = 0
        reply[:ctime] = 0
        reply[:atime] = 0
        reply[:mtime_seconds] = 0
        reply[:ctime_seconds] = 0
        reply[:atime_seconds] = 0
        reply[:md5] = 0
        reply[:uid] = 0
        reply[:gid] = 0

        if File.exists?(file)
          Log.debug("Asked for status of '#{file}' - it is present")
          reply[:output] = "present"
          reply[:present] = 1

          if File.symlink?(file)
            stat = File.lstat(file)
          else
            stat = File.stat(file)
          end

          [:size, :mtime, :ctime, :atime, :uid, :gid].each do |item|
            reply[item] = stat.send(item)
          end

          [:mtime, :ctime, :atime].each do |item|
            reply["#{item}_seconds".to_sym] = stat.send(item).to_i
          end

          reply[:mode] = "%o" % [stat.mode]
          reply[:md5] = Digest::MD5.hexdigest(File.read(file)) if stat.file?

          reply[:type] = "directory" if stat.directory?
          reply[:type] = "file" if stat.file?
          reply[:type] = "symlink" if stat.symlink?
          reply[:type] = "socket" if stat.socket?
          reply[:type] = "chardev" if stat.chardev?
          reply[:type] = "blockdev" if stat.blockdev?

          if File.directory?(file) && request[:dirlist]
            dir_filelist = Dir.entries(file)
            # remove superfluous . and .. entries
            dir_filelist -= [".",".."]
            reply[:dir_listing] = dir_filelist
          end

        else
          Log.debug("Asked for status of '#{file}' - it is not present")
          reply.fail! "#{file} does not exist"
        end
      end

      def remove
        file = get_filename

        if File.exists?(file) || File.symlink?(file)
          begin
            FileUtils.rm(file)
            Log.debug("Removed file '#{file}'")
            reply.statusmsg = "OK"
          rescue Exception => e
            Log.warn("Could not remove file '#{file}': #{e.class}: #{e}")
            reply.fail! "Could not remove file '#{file}': #{e.class}: #{e}"
          end
        else
          Log.debug("Asked to remove file '#{file}', but it does not exist")
          reply.fail! "Could not remove file '#{file}' - it is not present"
        end
      end

      def touch
        file = get_filename

        begin
          FileUtils.touch(file)
          Log.debug("Touched file '#{file}'")
        rescue Exception => e
          Log.warn("Could not touch file '#{file}': #{e.class}: #{e}")
          reply.fail! "Could not touch file '#{file}': #{e.class}: #{e}"
        end
      end
    end
  end
end

