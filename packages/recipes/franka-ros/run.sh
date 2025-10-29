
micromamba run -n ros_noetic bash -c "
cd ~/ws_franka_ros
source setup_env.sh
roslaunch franka_example_controllers move_to_start.launch robot_ip:=172.16.0.2
"