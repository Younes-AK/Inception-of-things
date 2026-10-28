
Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"
  config.vm.hostname = "iot-host-vm"
  
  config.vm.network "forwarded_port", guest: 8081, host: 8081, host_ip: "127.0.0.1"  

  # Access Argo CD UI and p3 app from the host browser
  config.vm.network "forwarded_port", guest: 8080, host: 8080
  config.vm.network "forwarded_port", guest: 8889, host: 8889

  config.vm.provider "virtualbox" do |vb|
    vb.name = "iot-host-vm"
    vb.cpus = 2
    vb.memory= 4096

    # Enable nested virtualization
    # vb.customize ["modifyvm", :id, "--nested-hw-virt", "on"]
  end

  # reset: true reopens the SSH connection so the new docker group applies.
  config.vm.provision "shell", path: "./IOT/p3/scripts/install.sh", reset: true
  config.vm.provision "shell", path: "./IOT/p3/scripts/setup.sh", privileged: false
end
