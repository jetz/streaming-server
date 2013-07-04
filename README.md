说明：本程序在Linux上开发，运行环境也在Linux环境下。

1. 首先，确保Erlang已经安装，并配置好环境安装完毕。Ubuntu默认安装有Erlang，在终端数据erl即可进入交互环境。
2. 打开文件mp3_parser.erl把第十行的/home/jetz/music_test改为mp3文件所在目录。打开文件tag_len.erl同样把第九行/home/jetz/music_test该为mp3文件所在目录，保存退出。打开终端，进入代码目录，执行make命令，这样会在beam文件夹内生成相应的*.beam文件，该文件即为代码生成的供erl执行文件。
3. 在beam文件夹内打开终端，输入erl进入Erlang交互模式。然后执行输入"mp3_parser:dump_data()."（注意最后的点号标示结束），生成mp3文件列表，这时会在当前文件生成一个mp3data.tmp的文件。mp3data.tmp中包含了每一首mp3的位置，名称，音轨，专辑等，可打开具体查看。
4. 生成播放列表文件后，可以进行测试，查看每个mp3的tag，具体操作：在交互端输入："tag_len:test()."，即可输出所有mp3tag信息。可以看出，有些mp3的ID3tag格式由于不是ID3v1或者ID3v1.1会提示有奇怪的开始标示，而出现错误。
5. 接下来就可以输入："shout_server:start()."开启音频数据流服务器。服务器为后台守护进程，开启后可以在客户端输入地址"http://localhost:3000"来进行音乐播放，如果在其他机器上可以输入服务器所在机器的ip地址然后输入端口3000来进行播放。