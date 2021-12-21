require 'optparse'

# Support overriding cpus/ram via command line, for example:
# vagrant up --cpus 8 --ram 4096
def parse_resources
    cpus = 4
    ram = 8192
    opt_parser = OptionParser.new do |opts|
        opts.on("--cpus cpus") do |c|
            cpus = Integer(c)
        end
        opts.on("--ram ram") do |r|
            ram = Integer(r)
        end
    end
    opt_parser.parse!(ARGV)
    [cpus, ram]
end
CPUS, RAM = parse_resources

Vagrant.configure("2") do |config|
    config.vm.box = "comnetsemu-0.2.0"

    config.vagrant.plugins = ["vagrant-vbguest"]

    if Vagrant.has_plugin?("vagrant-vbguest")
        config.vbguest.auto_update = false
    end

    config.vm.define "comnetsemu-srsran" do |cs|
        cs.vm.synced_folder ".", "/home/vagrant/project", type: "rsync", 
            rsync__auto: true,
            rsync__exclude: ["comnetsemu", "build/*.box"]

        cs.vm.provider "virtualbox" do |vb|
            vb.name = "comnetsemu-srsran"
            vb.cpus = CPUS
            vb.memory = RAM
            # MARK: The CPU should enable SSE3 or SSE4 to compile DPDK applications.
            vb.customize ["setextradata", :id, "VBoxInternal/CPUM/SSE4.1", "1"]
            vb.customize ["setextradata", :id, "VBoxInternal/CPUM/SSE4.2", "1"]
        end
    end
end
