# knife-vagrant
# knife plugin for spinning up a vagrant instance and testing a runlist.

module KnifePlugins
  class VagrantTest < Chef::Knife

    banner "knife vagrant test (options)"

    deps do
      require 'rubygems'
      require 'pp'
      require 'vagrant'
      require 'vagrant/cli'
      require 'chef/node'
      require 'chef/api_client'
    end

    # Default is nil here because if :cwd passed to the Vagrant::Environment object is nil,
    # it defaults to Dir.pwd, which is the cwd of the running process.
    option :vagrant_dir,
      :short => '-D PATH',
      :long => '--vagrant-dir PATH',
      :description => "Path to vagrant project directory.  Defaults to cwd (#{Dir.pwd}) if not specified",
      :default => Dir.pwd

    option :vagrant_run_list,
      :short => "-r RUN_LIST",
      :long => "--vagrant-run-list RUN_LIST",
      :description => "Comma separated list of roles/recipes to apply",
      :proc => lambda { |o| o.split(/[\s,]+/) },
      :default => []

    option :box,
      :short => '-b BOX',
      :long => '--box BOX',
      :description => 'Name of vagrant box to be provisioned',
      :default => false

    option :hostname,
      :short => '-H HOSTNAME',
      :long => '--hostname HOSTNAME',
      :description => 'Hostname to be set as hostname on vagrant box when provisioned',
      :default => 'vagrant-test'

    option :box_url,
      :short => '-U URL',
      :long => '--box-url URL',
      :description => 'URL of pre-packaged vbox template.  Can be a local path or an HTTP URL.  Defaults to ./package.box',
      :default => "#{Dir.pwd}/package.box"

    option :memsize,
      :short => '-m MEMORY',
      :long => '--memsize MEMORY',
      :description => 'Amount of RAM to allocate to provisioned VM, in MB.  Defaults to 1024',
      :default => 1024

    option :chef_loglevel,
      :short => '-l LEVEL',
      :long => '--chef-loglevel LEVEL',
      :description => 'Logging level for the chef-client process that runs inside the provisioned VM.  Default is INFO',
      :default => 'INFO'

    option :destroy,
      :short => '-x',
      :long => '--destroy',
      :description => 'Destroy vagrant box and delete chef node/client when finished',
      :default => false

    # TODO - hook into chef/runlist
    def build_runlist(runlist)
      runlist.collect { |i| "\"#{i}\"" }.join(",\n")
    end

    # TODO:  see if there's a way to pass this whole thing in as an object or hash or something, instead of writing a file to disk.
    def build_vagrantfile
      file = <<-EOF
        Vagrant::Config.run do |config|
          config.vm.forward_port(22, 2222)
          config.vm.box = "#{config[:box]}"
          config.vm.host_name = "#{config[:hostname]}"
          config.vm.customize [ "modifyvm", :id, "--memory", #{config[:memsize]} ]
          config.vm.customize [ "modifyvm", :id, "--name", "#{config[:box]}" ]
          config.vm.box_url = "#{config[:box_url]}"
          config.vm.provision :chef_client do |chef|
            chef.chef_server_url = "#{Chef::Config[:chef_server_url]}"
            chef.validation_key_path = "#{Chef::Config[:validation_key]}"
            chef.validation_client_name = "#{Chef::Config[:validation_client_name]}"
            chef.node_name = "#{config[:hostname]}"
            chef.log_level = :#{config[:chef_loglevel].downcase}
            chef.run_list = [
              #{build_runlist(config[:vagrant_run_list])}
            ]
          end
        end
      EOF
      file
    end

    def write_vagrantfile(path, content)
      File.open(path, 'w') { |f| f.write(content) }
    end

    def vagrant
      @vagrant_env ||= Vagrant::Environment.new(:cwd => config[:vagrant_dir], :ui_class => Vagrant::UI::Colored)
    end

    def cleanup(path)
      yes = config[:yes]
      config[:yes] = true
      vagrant.cli %w[destroy --force]
      File.delete(path)
      delete_object(Chef::Node, config[:hostname])
      delete_object(Chef::ApiClient, config[:hostname])
      config[:yes] = yes
      @vagrant_env = nil
    end

    def run
      Dir.chdir(config[:vagrant_dir])
      vagrantfile = "#{config[:vagrant_dir]}/Vagrantfile"
      ui.msg('Loading vagrant environment...')

      if File.exist?(vagrantfile)
        ui.msg('Vagrantfile already exists, cleaning up last run...')
        cleanup(vagrantfile)
      end

      write_vagrantfile(vagrantfile, build_vagrantfile)
      vagrant.load!
      begin
        vagrant.cli('up')
      rescue
        raise # I'll put some error handling here later.
      ensure
        if config[:destroy]
          ui.confirm("Destroy vagrant box #{config[:box]} and delete chef node and client")
          cleanup(vagrantfile)
        end
      end
    end

  end
end
