# Netdisco设备标签属性插件
# 此模块提供设备标签属性功能，用于根据配置规则自动为设备和端口设置标签
package App::Netdisco::Worker::Plugin::Discover::Properties::Tags;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Dancer::Plugin::DBIC 'schema';
use App::Netdisco::Util::Web 'sort_port';
use App::Netdisco::Util::Permission 'acl_matches';

# 注册主阶段工作器 - 设置设备标签
register_worker(
  {phase => 'main', title => 'device tags'},  # 主阶段，设备标签
  sub {
    my ($job, $workerconf) = @_;
    my $device = $job->device;
    return unless $device->in_storage;  # 确保设备已存储

    # 检查标签配置是否存在
    return
          unless setting('tags')                    # 标签设置存在
      and ref {} eq ref setting('tags')             # 标签设置是哈希引用
      and exists setting('tags')->{'device'}        # 设备标签配置存在
      and ref {} eq ref setting('tags')->{'device'}; # 设备标签配置是哈希引用

    my $tags        = setting('tags')->{'device'};  # 获取设备标签配置
    my @tags_to_set = ();                           # 要设置的标签列表

    # 遍历所有标签配置
    foreach my $tag (sort keys %$tags) {

      # 左侧是标签，右侧匹配设备
      next unless acl_matches($device, $tags->{$tag});  # 检查设备是否匹配标签规则
      push @tags_to_set, $tag;  # 添加匹配的标签
    }

    return unless scalar @tags_to_set;  # 如果没有标签要设置则返回
    $device->update({tags => \@tags_to_set});  # 更新设备标签
    debug sprintf ' [%s] properties - set %s tag%s', $device->ip, scalar @tags_to_set, (scalar @tags_to_set > 1);
  }
);

# 注册主阶段工作器 - 设置设备端口标签
register_worker(
  {phase => 'main', title => 'device port tags'},  # 主阶段，设备端口标签
  sub {
    my ($job, $workerconf) = @_;
    my $device = $job->device;
    return unless $device->in_storage;  # 确保设备已存储

    # 检查端口标签配置是否存在
    return
          unless setting('tags')                        # 标签设置存在
      and ref {} eq ref setting('tags')                 # 标签设置是哈希引用
      and exists setting('tags')->{'device_port'}       # 设备端口标签配置存在
      and ref {} eq ref setting('tags')->{'device_port'}; # 设备端口标签配置是哈希引用

    my $tags        = setting('tags')->{'device_port'}; # 获取设备端口标签配置
    my %tags_to_set = ();                              # 要设置的标签哈希
    my $port_map    = {};                              # 端口映射

    # 钩子数据出现在早期阶段的Properties工作器之后
    map { push @{$port_map->{$_->{port}}}, $_ } @{vars->{'hook_data'}->{'ports'} || []},
      grep { defined $_->{port} } @{vars->{'hook_data'}->{'device_ips'} || []};

    # 遍历所有端口标签配置
    foreach my $tag (sort keys %$tags) {

      # 左侧是标签，右侧是ACL映射
      my $maps = (ref {} eq ref $tags->{$tag}) ? [$tags->{$tag}] : ($tags->{$tag} || []);

      foreach my $map (@$maps) {
        foreach my $key (sort keys %$map) {

          # 左侧匹配设备，右侧匹配端口
          next unless $key and $map->{$key};
          next unless acl_matches($device, $key);  # 检查设备是否匹配

          foreach my $port (sort { sort_port($a, $b) } keys %$port_map) {
            next unless acl_matches($port_map->{$port}, $map->{$key});  # 检查端口是否匹配

            push @{$tags_to_set{$port}}, $tag;  # 添加匹配的标签到端口
          }
        }
      }
    }

    # 更新每个端口的标签
    foreach my $port (sort keys %tags_to_set) {
      schema('netdisco')
        ->resultset('DevicePort')
        ->search({ip   => $device->ip, port => $port}, {for => 'update'})
        ->update({tags => ($tags_to_set{$port} || [])});

      debug sprintf ' [%s] properties - set %s tag%s on port %s', $device->ip, scalar @{$tags_to_set{$port}},
        (scalar @{$tags_to_set{$port}} > 1), $port;
    }
  }
);

true;
