package App::Netdisco::DB::Result::Virtual::DeviceLinks;

# 设备链路虚拟结果类
# 提供设备间链路连接的虚拟视图，包括聚合链路信息

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

# 给未来开发者的注释：
# 此查询不使用device_port表中的slave_of字段来分组端口
# 因为我们实际需要的是设备间所有链路的总体带宽，无论这些链路是否在聚合中

__PACKAGE__->table('device_links');
__PACKAGE__->result_source_instance->is_virtual(1);
# 虚拟视图定义：设备链路连接
# 使用CTE（公共表表达式）分析设备间的双向链路连接，包括聚合链路统计
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
  WITH BothWays AS
    ( SELECT ldp.ip AS left_ip,
             ld.dns AS left_dns,
             ld.name AS left_name,
             array_agg(ldp.port ORDER BY ldp.port) AS left_port,
             array_agg(ldp.name ORDER BY ldp.name) AS left_descr,

             count(ldpp.*) AS aggports,
             sum(COALESCE(ldpp.raw_speed, 0)) AS aggspeed,

             di.ip AS right_ip,
             rd.dns AS right_dns,
             rd.name AS right_name,
             array_agg(ldp.remote_port ORDER BY ldp.remote_port) AS right_port,
             array_agg(rdp.name ORDER BY rdp.name) AS right_descr

     FROM device_port ldp

     LEFT OUTER JOIN device_port_properties ldpp ON (
        (ldp.ip = ldpp.ip) AND (ldp.port = ldpp.port)
        AND (ldp.type IS NULL
             OR ldp.type !~* '^(53|ieee8023adLag|propVirtual|l2vlan|l3ipvlan|135|136|137)\$')
        AND (ldp.is_master = 'false'
             OR ldp.slave_of IS NOT NULL) )

     INNER JOIN device ld ON ldp.ip = ld.ip
     INNER JOIN
      (SELECT ip, alias FROM device_ip WHERE alias IN
        (SELECT alias FROM device_ip GROUP BY alias HAVING count(alias) = 1)) di
        ON ldp.remote_ip = di.alias
     INNER JOIN device rd ON di.ip = rd.ip

     LEFT OUTER JOIN device_port rdp ON (di.ip = rdp.ip
                                         AND ((ldp.remote_port = rdp.port)
                                              OR (ldp.remote_port = rdp.name)
                                              OR (ldp.remote_port = rdp.descr)))

     WHERE ldp.remote_port IS NOT NULL
       AND ldp.port !~* 'vlan'
       AND (ldp.descr IS NULL OR ldp.descr !~* 'vlan')

     GROUP BY left_ip,
              left_dns,
              left_name,
              right_ip,
              right_dns,
              right_name )

  SELECT *
  FROM BothWays b
  WHERE NOT EXISTS
      ( SELECT *
       FROM BothWays b2
       WHERE b2.right_ip = b.left_ip
         AND b2.right_port = b.left_port
         AND b2.left_ip < b.left_ip )
  ORDER BY aggspeed DESC, 1, 2
ENDSQL
);

# 定义虚拟视图的列
# 包含链路两端设备的IP、DNS、名称、端口和聚合信息
__PACKAGE__->add_columns(
  'left_ip' => {
    data_type => 'inet',
  },
  'left_dns' => {
    data_type => 'text',
  },
  'left_name' => {
    data_type => 'text',
  },
  'left_port' => {
    data_type => '[text]',
  },
  'left_descr' => {
    data_type => '[text]',
  },
  'aggspeed' => {
    data_type => 'bigint',
  },
  'aggports' => {
    data_type => 'integer',
  },
  'right_ip' => {
    data_type => 'inet',
  },
  'right_dns' => {
    data_type => 'text',
  },
  'right_name' => {
    data_type => 'text',
  },
  'right_port' => {
    data_type => '[text]',
  },
  'right_descr' => {
    data_type => '[text]',
  },
);

# 定义关联关系：左侧设备端口VLAN
# 通过IP地址和端口数组匹配左侧设备的VLAN信息
__PACKAGE__->has_many('left_vlans', 'App::Netdisco::DB::Result::DevicePortVlan',
  sub {
    my $args = shift;
    return {
      "$args->{foreign_alias}.ip" => { -ident => "$args->{self_alias}.left_ip" },
      "$args->{self_alias}.left_port" => { '@>' => \"ARRAY[$args->{foreign_alias}.port]" },
    };
  }
);

# 定义关联关系：右侧设备端口VLAN
# 通过IP地址和端口数组匹配右侧设备的VLAN信息
__PACKAGE__->has_many('right_vlans', 'App::Netdisco::DB::Result::DevicePortVlan',
  sub {
    my $args = shift;
    return {
      "$args->{foreign_alias}.ip" => { -ident => "$args->{self_alias}.right_ip" },
      "$args->{self_alias}.right_port" => { '@>' => \"ARRAY[$args->{foreign_alias}.port]" },
    };
  }
);

1;
