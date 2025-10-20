import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/vpn_server.dart';
// import '../../core/models/vpngate_server.dart';

class ServerListScreen extends ConsumerStatefulWidget {
  final List<VpnServer> servers;
  final void Function(VpnServer) onSelect;
  const ServerListScreen({super.key, required this.servers, required this.onSelect});

  @override
  ConsumerState<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends ConsumerState<ServerListScreen> {
  List<VpnServer> _filteredServers = [];
  String _searchQuery = '';
  String _selectedCountry = 'All';

  @override
  void initState() {
    super.initState();
    _filteredServers = widget.servers;
  }

  void _filterServers() {
    setState(() {
      _filteredServers = widget.servers.where((server) {
        final matchesSearch = _searchQuery.isEmpty ||
            server.country.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            server.ip.contains(_searchQuery);
        
        final matchesCountry = _selectedCountry == 'All' ||
            server.country == _selectedCountry;
        
        return matchesSearch && matchesCountry;
      }).toList();
    });
  }

  List<String> get _countries {
    final countries = widget.servers.map((s) => s.country).toSet().toList();
    countries.sort();
    return ['All', ...countries];
  }

  Widget _buildServerCard(VpnServer server) {
    final speedMbps = server.speedMbps.toStringAsFixed(1);
    final isFast = server.isFast;
    final isVeryFast = server.isVeryFast;
    
    Color speedColor;
    IconData speedIcon;
    String speedLabel;
    
    if (isVeryFast) {
      speedColor = const Color(0xFF00C851);
      speedIcon = Icons.flash_on_rounded;
      speedLabel = 'Very Fast';
    } else if (isFast) {
      speedColor = const Color(0xFFFF8800);
      speedIcon = Icons.speed_rounded;
      speedLabel = 'Fast';
    } else {
      speedColor = const Color(0xFF757575);
      speedIcon = Icons.network_check_rounded;
      speedLabel = 'Good';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(20),
        leading: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                speedColor.withValues(alpha: 0.2),
                speedColor.withValues(alpha: 0.1),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: speedColor.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                speedIcon,
                color: speedColor,
                size: 20,
              ),
              const SizedBox(height: 2),
              Text(
                speedLabel,
                style: TextStyle(
                  color: speedColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.country,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${server.protocolIcon} ${server.protocolName}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: speedColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${server.pingMs ?? 9999}ms',
                style: TextStyle(
                  color: speedColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              server.ip,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.speed_rounded,
                  size: 16,
                  color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  '$speedMbps Mbps',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.star_rounded,
                  size: 16,
                  color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  'Score: ${server.score ?? 0}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.arrow_forward_ios_rounded,
            size: 16,
            color: Color(0xFF2196F3),
          ),
        ),
        onTap: () => widget.onSelect(server),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        onChanged: (value) {
          _searchQuery = value;
          _filterServers();
        },
        decoration: InputDecoration(
          hintText: 'Search servers by country or IP...',
          hintStyle: TextStyle(
            color: Theme.of(context).hintColor,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: Theme.of(context).hintColor,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(20),
        ),
        style: TextStyle(
          color: Theme.of(context).textTheme.bodyMedium?.color,
        ),
      ),
    );
  }

  Widget _buildCountryFilter() {
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _countries.length,
        itemBuilder: (context, index) {
          final country = _countries[index];
          final isSelected = country == _selectedCountry;
          
          return Container(
            margin: const EdgeInsets.only(right: 12),
            child: FilterChip(
              label: Text(
                country,
                style: TextStyle(
                  color: isSelected 
                      ? Colors.white
                      : Theme.of(context).textTheme.bodyMedium?.color,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _selectedCountry = country;
                });
                _filterServers();
              },
              backgroundColor: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.grey[800] 
                  : Colors.grey[200],
              selectedColor: Theme.of(context).primaryColor,
              checkmarkColor: Colors.white,
              side: BorderSide(
                color: isSelected 
                    ? Theme.of(context).primaryColor 
                    : Theme.of(context).dividerColor.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Server List',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(),
            const SizedBox(height: 8),
            _buildCountryFilter(),
            const SizedBox(height: 16),
            Expanded(
              child: _filteredServers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 64,
                            color: Theme.of(context).textTheme.bodyLarge?.color?.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No servers found',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Theme.of(context).textTheme.bodyLarge?.color?.withValues(alpha: 0.5),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Try adjusting your search or filter',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredServers.length,
                      itemBuilder: (context, index) {
                        return _buildServerCard(_filteredServers[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}