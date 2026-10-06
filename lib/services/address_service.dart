import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SavedAddress {
  final String id, label, address, phone;
  final double? lat, lng;
  final bool isDefault;
  SavedAddress({required this.id, required this.label, required this.address, required this.phone, this.lat, this.lng, required this.isDefault});
  factory SavedAddress.fromDoc(DocumentSnapshot<Map<String,dynamic>> d) {
    final x=d.data() ?? {};
    return SavedAddress(id:d.id,label:x['label']?.toString()??'Home',address:x['address']?.toString()??'',phone:x['phone']?.toString()??'',lat:(x['lat'] as num?)?.toDouble(),lng:(x['lng'] as num?)?.toDouble(),isDefault:x['isDefault']==true);
  }
}
class AddressService {
  final db=FirebaseFirestore.instance;
  String get uid=>FirebaseAuth.instance.currentUser!.uid;
  Stream<List<SavedAddress>> watch() => db.collection('users').doc(uid).collection('addresses').orderBy('isDefault',descending:true).orderBy('createdAt',descending:true).snapshots().map((s)=>s.docs.map(SavedAddress.fromDoc).toList());
  Future<void> save({String? id,required String label,required String address,required String phone,double? lat,double? lng,bool isDefault=false}) async {
    final ref=db.collection('users').doc(uid).collection('addresses').doc(id);
    final data={'label':label.trim(),'address':address.trim(),'phone':phone.trim(),'lat':lat,'lng':lng,'isDefault':isDefault,'updatedAt':FieldValue.serverTimestamp()};
    if(isDefault){final batch=db.batch(); final old=await db.collection('users').doc(uid).collection('addresses').where('isDefault',isEqualTo:true).get(); for(final d in old.docs){if(d.id!=ref.id) batch.update(d.reference,{'isDefault':false});} batch.set(ref,{...data,'createdAt':FieldValue.serverTimestamp()},SetOptions(merge:true)); await batch.commit();} else {await ref.set({...data,'createdAt':FieldValue.serverTimestamp()},SetOptions(merge:true));}
  }
  Future<void> remove(String id)=>db.collection('users').doc(uid).collection('addresses').doc(id).delete();
  Future<void> makeDefault(SavedAddress a)=>save(id:a.id,label:a.label,address:a.address,phone:a.phone,lat:a.lat,lng:a.lng,isDefault:true);
}
