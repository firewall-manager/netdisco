# Netdisco 库存管理插件
# 此模块提供网络设备库存统计功能，包括设备平台和操作系统版本统计
package App::Netdisco::Web::Plugin::Inventory;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

# 注册导航栏项目 - 库存管理页面入口
register_navbar_item({
  tag   => 'inventory',
  path  => '/inventory',
  label => 'Inventory',
});

# 库存管理主页面路由 - 需要用户登录
get '/inventory' => require_login sub {
    # 获取设备平台和操作系统版本数据
    my $platforms = schema(vars->{'tenant'})->resultset('Virtual::DevicePlatforms');
    my $releases = schema(vars->{'tenant'})->resultset('Device')->get_releases();

    # 创建操作系统版本映射表，用于版本排序和分组
    # 将版本号格式化为可排序的字符串（数字部分补零）
    my %release_version_map = (
      map  { (join '', map {sprintf '%05s', $_} split m/(\D)/, ($_->{os_ver} || '')) => $_ }
      $releases->hri->all
    );

    # 按操作系统类型分组版本信息
    my %release_map = ();
    map  { push @{ $release_map{ $release_version_map{$_}->{os} } }, $release_version_map{$_} }
    grep { $release_version_map{$_}->{os} }
    grep { $_ }
    sort {(lc($release_version_map{$a}->{os} || '') cmp lc($release_version_map{$b}->{os} || '')) || ($a cmp $b)}
         keys %release_version_map;

    # 计算每个操作系统类型的统计信息（行数和设备总数）
    my %release_totals =
      map  { $_ => {rows => scalar @{ $release_map{$_} }, count => 0} }
           keys %release_map;

    # 累加每个操作系统类型的设备数量
    foreach my $r (keys %release_totals) {
      map { $release_totals{$r}->{count} += $_->{count} }
          @{ $release_map{ $r } };
    }

    # 按厂商分组设备平台信息
    my %platform_map = ();
    map  { push @{ $platform_map{$_->{vendor}} }, $_ }
    grep { $_->{vendor} }
    grep { $_ }
    sort {(lc($a->{vendor} || '') cmp lc($b->{vendor} || '')) || (lc($a->{model} || '') cmp lc($b->{model} || ''))}
         $platforms->hri->all;

    # 计算每个厂商的统计信息（行数和设备总数）
    my %platform_totals =
      map  { $_ => {rows => scalar @{ $platform_map{$_} }, count => 0} }
           keys %platform_map;

    # 累加每个厂商的设备数量
    foreach my $r (keys %platform_totals) {
      map { $platform_totals{$r}->{count} += $_->{count} }
          @{ $platform_map{ $r } };
    }

    # 设置导航栏当前页面标识
    var(nav => 'inventory');
    
    # 渲染库存管理页面模板，传递所有统计数据
    template 'inventory', {
      platforms => [ sort keys %platform_totals ],      # 厂商列表（排序后）
      releases  => [ sort keys %release_totals ],       # 操作系统列表（排序后）
      platform_map => \%platform_map,                   # 厂商设备映射表
      release_map  => \%release_map,                    # 操作系统版本映射表
      platform_totals => \%platform_totals,             # 厂商统计信息
      release_totals  => \%release_totals,              # 操作系统统计信息
      unknown_platforms => ([grep { not $_->{vendor} } $platforms->hri->all]->[0]->{count} || 0),  # 未知厂商设备数量
      unknown_releases => ([grep { not $_->{os} } $releases->hri->all]->[0]->{count} || 0),        # 未知操作系统设备数量
    }, { layout => 'main' };
};

# 模块加载成功标识
true;
