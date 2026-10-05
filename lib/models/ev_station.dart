class EvStation {
  final String id;
  final int? ocmId;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String connectorTypes;
  final int totalPorts;
  final String? kwhRating;
  final String? operatorName;

  EvStation({
    required this.id,
    this.ocmId,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.connectorTypes,
    required this.totalPorts,
    this.kwhRating,
    this.operatorName,
  });

  factory EvStation.fromJson(Map<String, dynamic> json) {
    return EvStation(
      id: json['id'].toString(),
      ocmId: json['ocm_id'] != null
          ? int.tryParse(json['ocm_id'].toString())
          : null,
      name: json['name'] ?? 'Unnamed Station',
      address: json['address'] ?? '',
      latitude: double.parse(json['latitude'].toString()),
      longitude: double.parse(json['longitude'].toString()),
      connectorTypes: json['connector_types'] ?? 'Unknown',
      totalPorts: int.tryParse(json['total_ports'].toString()) ?? 0,
      kwhRating: json['kwh_rating'],
      operatorName: json['operator'],
    );
  }
}