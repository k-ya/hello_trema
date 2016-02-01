#!/usr/bin/ruby
# -*- coding: shift_jis -*-

require "socket"
require "json"
require 'sys/filesystem'


json_file_path = 'vm_memories.json'

home = "C:\\Users\\yamanishi"
vms = home+"\\VirtualBox VMs"

ctrl_ip = "192.168.100.102"
port = 55555

$rest_memory = 10280
rest_volume = 102400

#容量は各時点での残りをfilesystemから取得する
#メモリの方はVM名ごとにメモリ数を管理
vm_memories = {}


# 読み込んで
json_data = open(json_file_path) do |io|
 vm_memories = JSON.load(io)
end

vm_memories.each_value{|value|
$rest_memory -= value
}

#

#---
#HOST_UPDATEコマンド
def host_update()
stat = Sys::Filesystem.stat('c:\\')
rest_volume = (stat.blocks_free * stat.block_size).to_f / 1024 / 1024 / 1024
rest_volume = rest_volume.to_s.scan(/^(\d+\.\d{0,3})/)[0][0].to_f
hash_host = {}
hash_host['function'] = "HOST_UPDATE"
host = {}
  host['host_id'] = '2'
  host['ip_address'] = '192.168.100.103'
  host['min_cpu'] = '1'
  host['max_cpu'] = '4'
  host['min_memory'] = '4'
  host['max_memory'] = '10280'
  host['min_volume'] = '2048'
  host['max_volume'] = '102400'
  host['rest_memory'] = $rest_memory
  host['rest_volume'] = rest_volume
hash_host['field'] = host
return hash_host.to_json
end


# クライアントからの接続を待つソケット
# 常に繰り返す



  p "tcpsocket open"
 begin
  sock = TCPSocket.open(ctrl_ip, port)
   rescue
  puts "TCPSocket.open failed : #$!\n"
 end
 m = host_update()
 p m
    sock.write(m)
  sock.close

while true
 message = ""
  p "server open"
  s0 = TCPServer.open(port)
  # クライアントからの接続をacceptする
  accept = s0.accept
  p "socket accept"

  str = ""
  # クライアントからのデータを全て受け取る
  while buf = accept.gets
#    p buf
    str += buf.to_s
  end

#=end
#str = ARGV[0]
#p "str = #{str}"
  #命令を読み込む
  json = JSON.parser.new(str)
  hash = json.parse()
  function = hash['function']
  user_id = hash['field']['user_id']
  vm_id = hash['field']['vm_id']
  vm_name = user_id+"_"+vm_id
  cpu = hash['field']['cpu']
  mac_address = hash['field']['mac_address']
   if mac_address != nil then mac_address = mac_address.gsub(":","") end
  memory = hash['field']['memory']
	if function == "VM_CREATE" and memory == nil 
		then memory = 1024 
	end
  volume = hash['field']['volume']


vm_folder = vms+"\\"+vm_name
p function 


#-------------------------------------------------------------------------------
case function
when 'VM_CREATE' then
#  cmd = "VBoxManage import #{home}\\ensyuuVB1.ova --vsys 0 "
  cmd = "VBoxManage import #{home}\\centos.ova --vsys 0 "
  if vm_name != nil then 
	cmd += "--vmname #{vm_name} " end
  if cpu !=nil then 
	cmd += "--cpus #{cpu} " end
  if memory !=nil then 
	cmd += "--memory #{memory} " end
  if vm_name != nil then 
	cmd += "--unit 11 --disk \"#{vm_folder}\\#{vm_name}-disk1.vdi\"" end
    p cmd
    stdout = `#{cmd}`
  if hash['field']['mac_address'] !=nil and $?.to_i==0 then stdout += `VBoxManage modifyvm #{vm_name} --macaddress1 #{mac_address} ` end
  if volume !=nil and $?.to_i==0#status=falseのときは右側のsystem()は実行されないはず
	 then stdout += `VBoxManage modifyhd \"#{vm_folder}\\#{vm_name}-disk1.vdi\" --resize #{volume}`end

  rest_memory -= memory.to_i
#  `vboxmanage modifyvm #{vm_name} --nic1 bridged --bridgeadapter1 \"Broadcom 802.11n ネットワーク アダプタ\"`

  vm_memories[vm_name] = memory.to_i
 message = host_update()

open(json_file_path,'w') do |io|
  JSON.dump(vm_memories, io)
end
#-------------------------------------------------------------------------------
when 'VM_MODIFY' then
  cmd = "VBoxManage modifyvm #{vm_name} "
  if cpu !=nil then cmd += "--cpus #{cpu} " end
  if hash['field']['mac_address'] !=nil then cmd += "--macaddress1 #{mac_address} " end
  if memory !=nil then 
	cmd += "--memory #{memory}" 
	  memory_change = memory.to_i - vm_memories[vm_name].to_i
	  vm_memories[vm_name] = memory
	  rest_memory -= memory_change
	 message = host_update()
	open(json_file_path,'w') do |io|
	    JSON.dump(vm_memories, io)
	  end
	end
     stdout = `#{cmd}`
  if volume !=nil and $?.to_i==0 then stdout += `VBoxManage modifyhd \"#{vm_folder}\\#{vm_name}-disk1.vdi\" --resize #{volume}` end

#-------------------------------------------------------------------------------
when 'VM_DELETE' then
  stdout = `VBoxManage unregistervm #{vm_name}`
p stdout
  stdout += `del \"#{vm_folder}\\#{vm_name}*\" \"#{vm_folder}\\*.vdi\"`
  rest_memory += vm_memories[vm_name].to_i
 message = host_update()
vm_memories[vm_name] = 0
open(json_file_path,'w') do |io|
  JSON.dump(vm_memories, io)
end

# {"function":"VM STATUS","field":f"user id":"user1","vms":[f"vm id":"vm001"g,f"vm id":"vm002"g,f"vm id":"vm003"g]}}

#-------------------------------------------------------------------------------
when 'VM_STATUS' then
out = `VBoxManage list runningvms`
hash['field']['vms'].each{|vm|		#vm = {"vm_id":"xx"}
	vmname = hash['field']['user_id']+"_"+vm['vm_id']
	n = out.index("\"#{vmname}\"")
	if n == nil then
		vm['status'] = "standby"
		else 
		vm['status'] = "running"
	end 
}

#-------------------------------------------------------------------------------
when 'VM_START' then
  stdout = `VBoxManage startvm #{vm_name}`

when 'VM_STOP' then
  stdout = `VBoxManage controlvm #{vm_name} poweroff`

#-------------------------------------------------------------------------------
when 'VM_RUNNING' then
stdout = is_running(vm_name)

else
  stdout =  "unavailable function."
end

#-------------------------------------------------------------------------------
  p "hash remake"
  hash['function'] += '_ACK'
  p "st"
  if $?.to_i == 0 then hash['status'] = 'OK'
  else hash['status'] = 'NG' end
  hash['message'] = stdout
# acceptしたソケットを閉じる
  accept.close
  s0.close

  p "tcpsocket open"
 begin
  sock = TCPSocket.open(ctrl_ip, port)
   rescue
  puts "TCPSocket.open failed : #$!\n"
 end
  result = hash.to_json 
  p result
  sock.write(result)
 if message != "" then sock.write(message) end
  sock.close


end
