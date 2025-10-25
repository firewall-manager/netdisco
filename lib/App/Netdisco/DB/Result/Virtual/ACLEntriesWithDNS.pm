package App::Netdisco::DB::Result::Virtual::ACLEntriesWithDNS;

# ACL条目与DNS虚拟结果类
# 提供带DNS解析的ACL条目虚拟视图

use strict;
use warnings;

use utf8;
use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('acl_entries_with_dns');
__PACKAGE__->result_source_instance->is_virtual(1);
# 虚拟视图定义：ACL条目与DNS解析
# 将ACL规则与设备DNS信息关联，提供完整的规则集
__PACKAGE__->result_source_instance->view_definition(<<'ENDSQL');
SELECT id,
      array_agg(ARRAY[
        acl.rule,
        CASE
          WHEN d2.ip IS NOT NULL
            THEN host(d2.ip)
          WHEN d3.ip IS NOT NULL
            THEN host(d3.ip)
          ELSE
            COALESCE(device_ip.dns,d1.dns,d1.name)
          END
      ]) AS ruleset
  FROM (SELECT id,
              unnest(rules) AS rule,
              generate_subscripts(rules, 1) AS idx
          FROM access_control_list
          ORDER BY idx ASC) acl
  LEFT JOIN device_ip
    ON acl.rule = host(device_ip.alias)
  LEFT JOIN device d1
    ON device_ip.ip = d1.ip
  LEFT JOIN device d2
    ON acl.rule = d2.dns
  LEFT JOIN device d3
    ON acl.rule = d3.name
  GROUP BY acl.id
ENDSQL

# 定义虚拟视图的列
# id: ACL条目ID
# ruleset: 规则集数组，包含规则和对应的DNS名称
__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_nullable => 0 },
  "ruleset",
  { data_type => "[text,text]", is_nullable => 0 },
);

1;
