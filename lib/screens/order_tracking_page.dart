import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/order.dart';
import '../services/location_service.dart';
import '../services/route_service.dart';

class OrderTrackingPage extends StatefulWidget {
  final OrderModel order;
  const OrderTrackingPage({super.key, required this.order});

  @override
  State<OrderTrackingPage> createState() => _OrderTrackingPageState();
}

class _OrderTrackingPageState extends State<OrderTrackingPage> {
  final LocationService _location = LocationService();
  final RouteService _routes = RouteService();
  GoogleMapController? _map;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _orderSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _riderSub;
  late OrderModel _currentOrder;
  LatLng? _riderPosition;
  LatLng? _customerPosition;
  Set<Polyline> _polylines = {};
  int? _etaSeconds;
  String? _distance;
  DateTime? _lastLocationUpdate;
  bool _loadingRoute = false;
  bool _locationUnavailable = false;

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
    _updateDestination();
    _watchOrder();
    _watchRider(_currentOrder.riderId);
  }

  void _updateDestination() {
    if (_currentOrder.deliveryLat != null && _currentOrder.deliveryLng != null) {
      _customerPosition = LatLng(
        _currentOrder.deliveryLat!,
        _currentOrder.deliveryLng!,
      );
    }
  }

  void _watchOrder() {
    _orderSub = FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.order.id)
        .snapshots()
        .listen((doc) {
      if (!doc.exists || !mounted) return;
      final next = OrderModel.fromDoc(doc);
      final riderChanged = next.riderId != _currentOrder.riderId;
      setState(() {
        _currentOrder = next;
        _updateDestination();
      });
      if (riderChanged) _watchRider(next.riderId);
    }, onError: (_) {
      if (mounted) setState(() => _locationUnavailable = true);
    });
  }

  void _watchRider(String riderId) {
    _riderSub?.cancel();
    _riderPosition = null;
    _lastLocationUpdate = null;
    _locationUnavailable = false;
    if (riderId.isEmpty) {
      if (mounted) setState(() {});
      return;
    }
    _riderSub = _location.watchRiderLocation(riderId).listen((doc) async {
      final data = doc.data();
      final lat = (data?['lat'] as num?)?.toDouble();
      final lng = (data?['lng'] as num?)?.toDouble();
      if (lat == null || lng == null || !mounted) return;
      final position = LatLng(lat, lng);
      final stamp = data?['updatedAt'];
      setState(() {
        _riderPosition = position;
        _lastLocationUpdate = stamp is Timestamp ? stamp.toDate() : null;
        _locationUnavailable = false;
      });
      await _refreshRoute(position);
    }, onError: (_) {
      if (mounted) setState(() => _locationUnavailable = true);
    });
  }

  Future<void> _refreshRoute(LatLng rider) async {
    final destination = _customerPosition;
    if (destination == null || _loadingRoute) return;
    _loadingRoute = true;
    try {
      final result = await _routes.getDrivingRoute(
        origin: rider,
        destination: destination,
      );
      if (!mounted || result == null) return;
      setState(() {
        _etaSeconds = result.durationSeconds;
        _distance = result.distanceText;
        _polylines = {
          Polyline(
            polylineId: const PolylineId('delivery_route'),
            points: result.points,
            width: 6,
          ),
        };
      });
      _fitBounds(rider, destination);
    } finally {
      _loadingRoute = false;
    }
  }

  void _fitBounds(LatLng a, LatLng b) {
    final controller = _map;
    if (controller == null) return;
    final bounds = LatLngBounds(
      southwest: LatLng(
        a.latitude < b.latitude ? a.latitude : b.latitude,
        a.longitude < b.longitude ? a.longitude : b.longitude,
      ),
      northeast: LatLng(
        a.latitude > b.latitude ? a.latitude : b.latitude,
        a.longitude > b.longitude ? a.longitude : b.longitude,
      ),
    );
    controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 70));
  }

  String _etaText() {
    if (_etaSeconds == null) return 'ETA unavailable';
    final minutes = (_etaSeconds! / 60).ceil();
    return minutes <= 1 ? 'Arriving in about 1 min' : 'ETA about $minutes min';
  }

  @override
  void dispose() {
    _orderSub?.cancel();
    _riderSub?.cancel();
    _map?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{};
    if (_customerPosition != null) {
      markers.add(Marker(
        markerId: const MarkerId('customer'),
        position: _customerPosition!,
        infoWindow: const InfoWindow(title: 'Delivery location'),
      ));
    }
    if (_riderPosition != null) {
      markers.add(Marker(
        markerId: const MarkerId('rider'),
        position: _riderPosition!,
        infoWindow: const InfoWindow(title: 'Rider'),
      ));
    }
    final center = _riderPosition ??
        _customerPosition ??
        const LatLng(31.5204, 74.3587);
    return Scaffold(
      appBar: AppBar(title: Text('Order #${_currentOrder.id.substring(0, 6)}')),
      body: Column(children: [
        Expanded(
          child: GoogleMap(
            initialCameraPosition: CameraPosition(target: center, zoom: 14),
            onMapCreated: (controller) {
              _map = controller;
              if (_riderPosition != null && _customerPosition != null) {
                _fitBounds(_riderPosition!, _customerPosition!);
              }
            },
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
            markers: markers,
            polylines: _polylines,
          ),
        ),
        Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Status: ${_currentOrder.status}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(_etaText(), style: const TextStyle(fontSize: 16)),
                if (_distance != null) Text('Distance: $_distance'),
                if (_lastLocationUpdate != null)
                  Text('Last GPS update: ${_lastLocationUpdate!.toLocal()}'),
                const SizedBox(height: 6),
                Text(_currentOrder.address),
                const SizedBox(height: 8),
                Text(
                  _riderPosition != null
                      ? 'Rider location is updating live.'
                      : _locationUnavailable
                          ? 'Rider location is temporarily unavailable. Please try again shortly.'
                          : _currentOrder.riderId.isEmpty
                              ? 'A rider has not been assigned yet.'
                              : 'Waiting for the rider to start location sharing.',
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}
