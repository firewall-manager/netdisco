package App::Netdisco::Web::Search;

# 搜索Web模块
# 提供网络设备搜索功能

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Util::Web 'sql_match';
use Regexp::Common 'net';
use NetAddr::MAC ();

# 模板前钩子
# 处理搜索页面的模板变量
hook 'before_template' => sub {
  my $tokens = shift;

  return
    unless (request->path eq uri_for('/search')->path
    or index(request->path, uri_for('/ajax/content/search')->path) == 0);

  # 用于设备搜索侧边栏模板设置选中项
  foreach my $opt (qw/model vendor os os_ver/) {
    my $p = (ref [] eq ref param($opt) ? param($opt) : (param($opt) ? [param($opt)] : []));
    $tokens->{"${opt}_lkp"} = {map { $_ => 1 } @$p};
  }
};

# 搜索页面路由
# 处理网络设备搜索请求
get '/search' => require_login sub {
  my $q = param('q');
  my $s = schema(vars->{'tenant'});

  if (not param('tab')) {
    if (not $q) {
      return redirect uri_for('/')->path;
    }

    # 为初始结果选择最可能的标签页
    if ($q =~ m/^[0-9]+$/ and $q < 4096) {
      params->{'tab'} = 'vlan';
    }
    else {
      my $nd = $s->resultset('Device')->search_fuzzy($q);
      my ($likeval, $likeclause) = sql_match($q);
      my $mac = NetAddr::MAC->new(mac => ($q || ''));

      # 验证MAC地址
      undef $mac
        if ($mac
        and $mac->as_ieee
        and (($mac->as_ieee eq '00:00:00:00:00:00') or ($mac->as_ieee !~ m/^$RE{net}{MAC}$/i)));

      if ($nd and $nd->count) {
        if ($nd->count == 1) {

          # 重定向到设备详情页面
          return redirect uri_for('/device', {tab => 'details', q => $nd->first->ip, f => '',})->path_query;
        }

        # 多个设备
        params->{'tab'} = 'device';
      }
      elsif (
        $s->resultset('DevicePort')->with_properties->search({
          -or => [
            {name                    => $likeclause},
            {'properties.remote_dns' => $likeclause},
            (((!defined $mac) or $mac->errstr) ? \['mac::text ILIKE ?', $likeval] : {mac => $mac->as_ieee}),
          ],
        })->count
      ) {

        params->{'tab'} = 'port';
      }
    }

    # 如果其他都失败
    params->{'tab'} ||= 'node';
  }

  # 用于设备搜索侧边栏填充选择输入
  my $model_list  = [grep {defined} $s->resultset('Device')->get_distinct_col('model')];
  my $os_list     = [grep {defined} $s->resultset('Device')->get_distinct_col('os')];
  my $vendor_list = [grep {defined} $s->resultset('Device')->get_distinct_col('vendor')];

  # 处理操作系统版本排序
  my %os_vermap = (
    map {
      $_ => (join '', map { sprintf '%05s', $_ } split m/(\D)/)
    } grep {defined} $s->resultset('Device')->get_distinct_col('os_ver')
  );
  my $os_ver_list = [sort { $os_vermap{$a} cmp $os_vermap{$b} } keys %os_vermap];

  template 'search', {
    search      => params->{'tab'},
    model_list  => $model_list,
    os_list     => $os_list,
    os_ver_list => $os_ver_list,
    vendor_list => $vendor_list,
    },
    {layout => 'main'};
};

true;
