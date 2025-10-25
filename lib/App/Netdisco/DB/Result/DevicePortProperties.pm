use utf8;
package App::Netdisco::DB::Result::DevicePortProperties;

# 设备端口属性结果类
# 提供设备端口扩展属性的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("device_port_properties");
# 定义表列
# 包含设备IP、端口、错误状态、远程设备信息和PAE认证信息
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "port",
  { data_type => "text", is_nullable => 0 },
  "error_disable_cause",
  { data_type => "text", is_nullable => 1 },
  "remote_is_discoverable",
  { data_type => "boolean", default_value => \"true",  is_nullable => 1 },
  "remote_is_wap",
  { data_type => "boolean", default_value => \"false", is_nullable => 1 },
  "remote_is_phone",
  { data_type => "boolean", default_value => \"false", is_nullable => 1 },
  "remote_vendor",
  { data_type => "text", is_nullable => 1 },
  "remote_model",
  { data_type => "text", is_nullable => 1 },
  "remote_os_ver",
  { data_type => "text", is_nullable => 1 },
  "remote_serial", 
  { data_type => "text", is_nullable => 1 },
  "remote_dns",
  { data_type => "text", is_nullable => 1 },
  "raw_speed",
  { data_type => "bigint", default_value => 0, is_nullable => 1 },
  "faststart",
  { data_type => "boolean", default_value => \"false", is_nullable => 1 },
  "ifindex",
  { data_type => "bigint", is_nullable => 1 },
  "pae_authconfig_state",
  { data_type => "text", is_nullable => 1 },      
  "pae_authconfig_port_control",
  { data_type => "text", is_nullable => 1 },
  "pae_authconfig_port_status",
  { data_type => "text", is_nullable => 1 },
  "pae_authsess_user",
  { data_type => "text", is_nullable => 1 },         
  "pae_authsess_mab",
  { data_type => "text", is_nullable => 1 },           
  "pae_last_eapol_frame_source",
  { data_type => "text", is_nullable => 1 },
  "pae_is_authenticator",
  { data_type => "boolean", default_value => \"false", is_nullable => 1 },
  "pae_is_supplicant",
  { data_type => "boolean", default_value => \"false", is_nullable => 1 },

);

# 设置主键
__PACKAGE__->set_primary_key("port", "ip");


=head1 RELATIONSHIPS

=head2 port

Returns the entry from the C<port> table for which this Power entry applies.

=cut

# 定义关联关系：端口
# 返回此属性条目适用的端口表条目
__PACKAGE__->belongs_to( port => 'App::Netdisco::DB::Result::DevicePort', {
  'foreign.ip' => 'self.ip', 'foreign.port' => 'self.port',
});

1;
