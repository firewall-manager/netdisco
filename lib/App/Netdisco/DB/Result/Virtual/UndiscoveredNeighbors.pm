package App::Netdisco::DB::Result::Virtual::UndiscoveredNeighbors;

# 未发现邻居虚拟结果类
# 提供未发现的网络邻居设备信息虚拟视图

use strict;
use warnings;

use utf8;
use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('undiscovered_neighbors');
__PACKAGE__->result_source_instance->is_virtual(1);
# 虚拟视图定义：未发现邻居
# 查找可发现但尚未发现的网络邻居设备
__PACKAGE__->result_source_instance->view_definition(<<'ENDSQL');
  SELECT DISTINCT ON (p.remote_ip, p.port)
    d.ip, d.name, d.dns,
    p.port, p.name AS port_description,
    p.remote_ip, p.remote_id, p.remote_type, p.remote_port,
    dpp.remote_is_discoverable, dpp.remote_is_wap, dpp.remote_is_phone, dpp.remote_dns,
    l.log AS comment,
    a.log, a.finished

  FROM device_port p

  INNER JOIN device d USING (ip)
  LEFT OUTER JOIN device_skip ds
    ON ('discover' = ANY(ds.actionset) AND p.remote_ip = ds.device)
  LEFT OUTER JOIN device_port_properties dpp USING (ip, port)
  LEFT OUTER JOIN device_port_log l USING (ip, port)
  LEFT OUTER JOIN admin a
    ON (p.remote_ip = a.device AND a.action = 'discover')

  WHERE
    ds.device IS NULL
    AND dpp.remote_is_discoverable
    AND ((p.remote_ip NOT IN (SELECT alias FROM device_ip))
         OR ((p.remote_ip IS NULL) AND p.is_uplink))

  ORDER BY
    p.remote_ip ASC,
    p.port ASC,
    l.creation DESC,
    a.finished DESC
ENDSQL

# 定义虚拟视图的列
# 包含设备信息、端口信息、远程设备信息和发现状态
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "name",
  { data_type => "text", is_nullable => 1 },
  "dns",
  { data_type => "text", is_nullable => 1 },
  "port",
  { data_type => "text", is_nullable => 0 },
  "port_description",
  { data_type => "text", is_nullable => 0 },
  "remote_ip",
  { data_type => "inet", is_nullable => 1 },
  "remote_port",
  { data_type => "text", is_nullable => 1 },
  "remote_type",
  { data_type => "text", is_nullable => 1 },
  "remote_id",
  { data_type => "text", is_nullable => 1 },
  "remote_is_discoverable",
  { data_type => "boolean", is_nullable => 1 },
  "remote_is_wap",
  { data_type => "boolean", is_nullable => 1 },
  "remote_is_phone",
  { data_type => "boolean", is_nullable => 1 },
  "remote_dns",
  { data_type => "text", is_nullable => 1 },
  "comment",
  { data_type => "text", is_nullable => 1 },
  "log",
  { data_type => "text", is_nullable => 1 },
  "finished",
  { data_type => "timestamp", is_nullable => 1 },
);

1;
