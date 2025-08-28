import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart';

Future<StripeData> FetchStripeData()async{
  FirebaseFirestore firestore = FirebaseFirestore.instance;

var ds = await firestore.collection('stripe_data').doc('JCfULLGTKtLFepPXZ40H').get();

return StripeData(subprice1ID: ds.get('sub1priceID'),
    subprice2ID: ds.get('sub2priceID')
);
}

class StripeData{
  String subprice1ID;
  String subprice2ID;

  StripeData({
    required this.subprice1ID,
    required this.subprice2ID,
});
}