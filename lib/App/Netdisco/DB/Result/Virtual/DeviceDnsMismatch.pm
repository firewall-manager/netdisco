package App::Netdisco::DB::Result::Virtual::DeviceDnsMismatch;

# 设备DNS不匹配虚拟结果类
# 提供DNS名称与设备名称不匹配的设备虚拟视图

use strict;
use warnings;

use utf8;
use base 'App::Netdisco::DB::Result::Device';

__PACKAGE__->load_components('Helper::Row::SubClass');
__PACKAGE__->subclass;

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');
__PACKAGE__->table('device_dns_mismatch');
__PACKAGE__->result_source_instance->is_virtual(1);

# 虚拟视图定义：设备DNS不匹配
# 查找DNS名称与设备名称不一致的设备，支持正则表达式清理
__PACKAGE__->result_source_instance->view_definition(<<'ENDSQL');
SELECT *
FROM device
WHERE dns IS NULL
  OR name IS NULL
  OR regexp_replace(lower(dns), ?, '')
    != regexp_replace(lower(name), ?, '')
ENDSQL

1;
