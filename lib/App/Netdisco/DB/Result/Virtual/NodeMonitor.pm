package App::Netdisco::DB::Result::Virtual::NodeMonitor;

# 节点监控虚拟结果类
# 提供节点监控信息的虚拟视图，包括监控原因和位置信息

use strict;
use warnings;

use utf8;
use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('node_monitor_virtual');
__PACKAGE__->result_source_instance->is_virtual(1);
# 虚拟视图定义：节点监控信息
# 关联节点监控、节点、设备和端口信息，提供完整的监控视图
__PACKAGE__->result_source_instance->view_definition(<<'ENDSQL');
SELECT nm.why, nm.cc, trim(trailing '.' from trim(trailing '0123456789' from date::text)) as date,
       n.mac, n.switch, n.port,
       d.name, d.location,
       dp.name AS portname
FROM node_monitor nm, node n, device d, device_port dp
WHERE ((nm.mac = n.mac) OR (nm.matchoui AND (substring(nm.mac::text from 1 for 8) = n.oui)))
  AND nm.active
  AND nm.cc IS NOT NULL
  AND d.ip = n.switch
  AND dp.ip = n.switch
  AND dp.port = n.port
  AND d.last_macsuck = n.time_last
ENDSQL

# 定义虚拟视图的列
# 包含监控原因、国家代码、日期、节点信息和设备信息
__PACKAGE__->add_columns(
  "why",
  { data_type => "text", is_nullable => 1 },
  "cc",
  { data_type => "text", is_nullable => 0 },
  "date",
  { data_type => "timestamp", is_nullable => 0 },
  "mac",
  { data_type => "macaddr", is_nullable => 0 },
  "switch",
  { data_type => "inet", is_nullable => 0 },
  "port",
  { data_type => "text", is_nullable => 0 },
  "name",
  { data_type => "text", is_nullable => 0 },
  "location",
  { data_type => "text", is_nullable => 1 },
  "portname",
  { data_type => "text", is_nullable => 0 },
);

1;
