# OEC_led_monitor_script
用于hoiw大佬为OEC/OECT适配的Armbian系统固件，利用网心云OEC/OECT 的三色LED显示系统状态。

原理：通过将0或1写入/sys/class/leds/xxx-led/brightness文件配置三原色的亮灭从而呈现7种颜色。

例如：echo 1 > /sys/class/leds/green-led/brightness

我让AI写了这个脚本，通过不同颜色显示系统的状态，并在晚上9点半到早上6点半之间关闭led灯不打扰我睡觉。

颜色如下：
```
红色 - CPU温度危险 (>80°C) - 最高优先级，需要立即处理
品红 - 内存高 + CPU负载高 - 系统性能严重问题
青色 - CPU负载过高 - 性能问题
白色 - 内存使用过高 - 资源警告
黄色 - 磁盘空间不足 - 存储警告
蓝色 - 网络断开 - 连接问题
绿色 - 系统正常 - 健康状态
```

ai时代真是好啊，像我这样完全不懂代码的人也能写脚本满足自己的需求了。欢迎任何人根据自己的需要使用，修改~（或者让AI帮你改）

## 安装方法：
```
# 复制脚本到系统目录
cp led_monitor_script.sh /usr/local/bin/
chmod +x /usr/local/bin/led_monitor_script.sh

# 复制服务文件
cp led_monitor.service /etc/systemd/system/

# 重新加载systemd配置
systemctl daemon-reload

# 启用服务（开机自启）
systemctl enable led_monitor.service

# 启动服务
systemctl start led_monitor.service

# 查看服务状态
systemctl status led_monitor.service

# 查看日志
sudo journalctl -u led_monitor.service -f

# 或查看脚本自己的日志
sudo tail -f /var/log/led_monitor.log

# 停止服务
sudo systemctl stop led_monitor.service

# 重启服务
sudo systemctl restart led_monitor.service

```



