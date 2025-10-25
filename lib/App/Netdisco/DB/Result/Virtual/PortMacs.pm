use utf8;
package App::Netdisco::DB::Result::Virtual::PortMacs;

# 端口MAC地址虚拟结果类
# 提供端口MAC地址信息的虚拟视图

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table("port_macs");
__PACKAGE__->result_source_instance->is_virtual(1);
# 虚拟视图定义：端口MAC地址
# 从设备和设备端口表中查找匹配的MAC地址
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
    SELECT ip, mac FROM device where mac = any (?::macaddr[])
      UNION
    SELECT ip, mac FROM device_port dp where mac = any (?::macaddr[])
ENDSQL
);

# 定义虚拟视图的列
# 包含MAC地址和IP地址信息
__PACKAGE__->add_columns(
  'mac' => { data_type => 'macaddr' },
  'ip'  => { data_type => 'inet' },
);

1;
