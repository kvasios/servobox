micromamba run -n ros_noetic bash -c "
cd ~/ws_franka_ros
source setup_env.sh
roslaunch serl_franka_controllers impedance.launch robot_ip:=172.16.0.2 load_gripper:=true
"