module FakeFS
  module FileUtils
    extend self

    # options: mode
    def mkdir_p(list, options = {})
      list = [*list]

      $stderr.puts "mkdir -p #{list.join ' '}" if options[:verbose]

      unless options[:noop]
        list.each_with_object([]) do |path, created|
          new_dir = FileSystem.add(path)
          created << new_dir.to_s
        end
      end

      list
    end
    alias_method :mkpath, :mkdir_p
    alias_method :makedirs, :mkdir_p

    # TODO: options[:mode]
    def mkdir(list, options = {})
      list = [*list]

      $stderr.puts "mkdir #{list.join ' '}" if options[:verbose]

      return nil if options[:noop]

      list.each_with_object([]) do |path, created|
        parent = path.split('/')
        parent.pop

        if FileSystem.find(path)
          raise Errno::EEXIST, path
        end

        unless ['', '.'].include?(parent.join '') || FileSystem.find(parent.join '/')
          raise Errno::ENOENT, path
        end

        new_dir = FileSystem.add(path, FakeDir.new)
        created << path
      end
    end

    def rmdir(list, options = {})
      list = [*list]

      $stderr.puts "rmdir #{list.join ' '}" if options[:verbose]

      return nil if options[:noop]

      list.each do |path|
        rm path
      end

      list
    end

    def rm(list, options = {})
      list = [*list]

      cmd = options[:force] ? 'rm -f' : 'rm'

      $stderr.puts "#{cmd} #{list.join ' '}" if options[:verbose]

      return nil if options[:noop]

      list.each do |path|
        unless FileSystem.delete(path) || options[:force]
          raise Errno::ENOENT, path
        end
      end

      list
    end
    alias_method :remove, :rm
    alias_method :rm_r, :rm

    def rm_f(list, options = {})
      rm list, options.merge(:force => true)
    end
    alias_method :safe_unlink, :rm_f

    def rm_rf(list, options = {})
      list = [*list]

      $stderr.puts "rm -rf #{list.join ' '}" if options.delete(:verbose)

      rm list, options.merge(:force => true)
    end
    alias_method :rmtree, :rm_rf

    def ln(src, dest, options = {})
      srcs = [*src]

      cmd = options[:force] ? 'ln -f' : 'ln'

      $stderr.puts "#{cmd} #{srcs.join ' '} #{dest}" if options.delete(:verbose)

      return nil if options[:noop]

      if src.is_a? Array
        ln_list srcs, dest, options
      else
        ln_file src, dest, options
      end
    end
    alias_method :link, :ln

    def ln_s(src, dest, options = {})
      srcs = [*src]

      cmd = options[:force] ? 'ln -sf' : 'ln -s'

      $stderr.puts "#{cmd} #{srcs.join ' '} #{dest}" if options[:verbose]

      return nil if options[:noop]

      if src.is_a? Array
        ln_list srcs, dest, options.merge(:symbolic => true)
      else
        ln_file src, dest, options.merge(:symbolic => true)
      end
    end
    alias_method :symlink, :ln_s

    def ln_file(src, dest, options = {})
      if FileSystem.find(dest) && !File.directory?(dest)
        raise Errno::EEXIST, dest unless options[:force]

        FileSystem.delete dest
      end

      raise Errno::ENOENT, "(#{src}, #{dest})" unless Dir.exists?(File.dirname(dest))

      dest_path = File.directory?(dest) ? File.join(dest, File.basename(src)) : dest

      file = options[:symbolic] ? FakeSymlink.new(src) : FileSystem.find(src).clone

      FileSystem.add dest_path, file

      return 0
    end

    def ln_list(list, destdir, options = {})
      list.each do |path|
        dest_path = File.join(destdir, File.basename(path))

        infos = [path, dest_path].join ', '

        raise Errno::ENOENT, "(#{infos})" unless FileSystem.find(destdir)
        raise Errno::ENOTDIR, "(#{infos})" unless File.directory?(destdir)

        file = options[:symbolic] ? FakeSymlink.new(path) : FileSystem.find(path).clone

        FileSystem.add(dest_path, file)
      end

      list
    end

    def ln_sf(target, path)
      ln_s(target, path, { :force => true })
    end

    def cp(src, dest)
      if src.is_a?(Array) && !File.directory?(dest)
        raise Errno::ENOTDIR, dest
      end

      Array(src).each do |src|
        dst_file = FileSystem.find(dest)
        src_file = FileSystem.find(src)

        if !src_file
          raise Errno::ENOENT, src
        end

        if File.directory? src_file
          raise Errno::EISDIR, src
        end

        if dst_file && File.directory?(dst_file)
          FileSystem.add(File.join(dest, src), src_file.entry.clone(dst_file))
        else
          FileSystem.delete(dest)
          FileSystem.add(dest, src_file.entry.clone)
        end
      end
    end

    def cp_r(src, dest)
      Array(src).each do |src|
        # This error sucks, but it conforms to the original Ruby
        # method.
        raise "unknown file type: #{src}" unless dir = FileSystem.find(src)

        new_dir = FileSystem.find(dest)

        if new_dir && !File.directory?(dest)
          raise Errno::EEXIST, dest
        end

        if !new_dir && !FileSystem.find(dest+'/../')
          raise Errno::ENOENT, dest
        end

        # This last bit is a total abuse and should be thought hard
        # about and cleaned up.
        if new_dir
          if src[-2..-1] == '/.'
            dir.entries.each{|f| new_dir[f.name] = f.clone(new_dir) }
          else
            new_dir[dir.name] = dir.entry.clone(new_dir)
          end
        else
          FileSystem.add(dest, dir.entry.clone)
        end
      end
    end

    def mv(src, dest, options={})
      Array(src).each do |path|
        if target = FileSystem.find(path)
          dest_path = File.directory?(dest) ? File.join(dest, File.basename(path)) : dest
          FileSystem.add(dest_path, target.entry.clone)
          FileSystem.delete(path)
        else
          raise Errno::ENOENT, path
        end
      end
    end

    def chown(user, group, list, options={})
      list = Array(list)
      list.each do |f|
        if File.exists?(f)
          uid = (user.to_s.match(/[0-9]+/) ? user.to_i : Etc.getpwnam(user).uid)
          gid = (group.to_s.match(/[0-9]+/) ? group.to_i : Etc.getgrnam(group).gid)
          File.chown(uid, gid, f)
        else
          raise Errno::ENOENT, f
        end
      end
      list
    end

    def chown_R(user, group, list, options={})
      list = Array(list)
      list.each do |file|
        chown(user, group, file)
        [FileSystem.find("#{file}/**/**")].flatten.each do |f|
          chown(user, group, f.to_s)
        end      
      end
      list
    end
    
    def chmod(mode, list, options={})
      list = Array(list)
      list.each do |f|
        if File.exists?(f)
          File.chmod(mode, f)
        else
          raise Errno::ENOENT, f
        end
      end
      list
    end
    
    def chmod_R(mode, list, options={})
      list = Array(list)
      list.each do |file|
        chmod(mode, file)
        [FileSystem.find("#{file}/**/**")].flatten.each do |f|
          chmod(mode, f.to_s)
        end      
      end
      list
    end

    def touch(list, options={})
      Array(list).each do |f|
        directory = File.dirname(f)
        # FIXME this explicit check for '.' shouldn't need to happen
        if File.exists?(directory) || directory == '.'
          FileSystem.add(f, FakeFile.new)
        else
          raise Errno::ENOENT, f
        end
      end
    end

    def cd(dir)
      FileSystem.chdir(dir)
    end
    alias_method :chdir, :cd
  end
end
