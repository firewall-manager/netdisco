package App::Netdisco::DB::ResultSet::PortCtlRole;

# 端口控制角色结果集类
# 提供端口控制角色相关的数据库查询功能

use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

__PACKAGE__->load_components(qw/
  +App::Netdisco::DB::ExplicitLocking
/);

=head1 ADDITIONAL METHODS

=cut

# 获取角色名称
# 返回所有唯一的角色名称列表，按名称排序
sub role_names  {
    my $self = shift;
    return $self->distinct('role_name')->order_by('role_name')->get_column('role_name')->all;
}

# 获取设备ACL
# 返回所有唯一的设备ACL ID列表
sub device_acls {
    my $self = shift;
    return $self->distinct('device_acl_id')->get_column('device_acl_id')->all;
}

# 获取端口ACL
# 返回所有唯一的端口ACL ID列表
sub port_acls {
    my $self = shift;
    return $self->distinct('port_acl_id')->get_column('port_acl_id')->all;
}

1;