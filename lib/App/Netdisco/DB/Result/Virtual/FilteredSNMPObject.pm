use utf8;
package App::Netdisco::DB::Result::Virtual::FilteredSNMPObject;

# 过滤的SNMP对象虚拟结果类
# 提供基于设备过滤的SNMP对象信息虚拟视图

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table("filtered_snmp_object");
__PACKAGE__->result_source_instance->is_virtual(1);

# 虚拟视图定义：过滤的SNMP对象
# 根据设备IP和OID深度过滤SNMP对象，统计浏览器中的对象数量
__PACKAGE__->result_source_instance->view_definition(
  <<ENDSQL

    SELECT so.oid, so.oid_parts, so.mib, so.leaf, so.type, so.access, so.index, so.status, so.enum, so.descr, so.num_children,
           count(db.oid) AS browser
      FROM snmp_object so

      LEFT JOIN device_browser db ON
           (db.ip = ? AND
            ((so.oid = db.oid)
              OR (array_length(db.oid_parts,1) > ?
                  AND db.oid LIKE so.oid || '.%')))

      WHERE array_length(so.oid_parts,1) = ?
            AND so.oid LIKE ?::text || '.%'

      GROUP BY so.oid, so.oid_parts, so.mib, so.leaf, so.type, so.access, so.index, so.status, so.enum, so.descr, so.num_children

ENDSQL
);

# 定义虚拟视图的列
# 包含SNMP对象的完整信息和浏览器统计
__PACKAGE__->add_columns(
  'oid'          => {data_type => 'text'},
  'oid_parts'    => {data_type => 'integer[]'},
  'mib'          => {data_type => 'text'},
  'leaf'         => {data_type => 'text'},
  'type'         => {data_type => 'text'},
  'access'       => {data_type => 'text'},
  'index'        => {data_type => 'text[]'},
  'status'       => {data_type => 'text'},
  'enum'         => {data_type => 'text[]'},
  'descr'        => {data_type => 'text'},
  'num_children' => {data_type => 'integer'},
  'browser'      => {data_type => 'integer'},
);

1;
