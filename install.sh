wget https://www.passmark.com/downloads/BurnInTest_Linux_x86-64.tar.gz
tar -xvf BurnInTest_Linux_x86-64.tar.gz
cd burnintest
sudo yum install qt5-qtsensors -y
sudo yum install qt5-qtlocation -y
sudo ./bit_gui_x64
