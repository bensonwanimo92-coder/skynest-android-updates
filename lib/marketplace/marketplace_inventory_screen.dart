import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Live public marketplace feed: only approved, unexpired adverts are queried.
class MarketplaceInventoryScreen extends StatefulWidget {
  const MarketplaceInventoryScreen({super.key});
  @override
  State<MarketplaceInventoryScreen> createState() => _MarketplaceInventoryScreenState();
}

class _MarketplaceInventoryScreenState extends State<MarketplaceInventoryScreen> {
  static const _website = 'https://bensonwanimo92-coder.github.io/';
  static const _categories = ['All categories','Residential','Commercial','Land','Development','Farms','Vehicles','Jobs','Restaurants','Hospitality','Products','Services','Luxury','Business','Other'];
  final _search = TextEditingController();
  String _category = 'All categories';
  late Stream<QuerySnapshot<Map<String, dynamic>>> _feed;

  @override
  void initState() { super.initState(); _refreshFeed(); }
  void _refreshFeed() {
    _feed = FirebaseFirestore.instance.collection('publicListings')
      .where('status', isEqualTo: 'approved')
      .where('expiresAt', isGreaterThan: Timestamp.now())
      .orderBy('expiresAt').orderBy('createdAt', descending: true)
      .limit(60).snapshots();
  }
  @override
  void dispose() { _search.dispose(); super.dispose(); }

  String _price(dynamic value) {
    final n = value is num ? value : num.tryParse(value?.toString() ?? '');
    return n == null || n <= 0 ? 'Contact for price' :
      NumberFormat.currency(locale: 'en_KE', symbol: 'KSh ', decimalDigits: 0).format(n);
  }
  List<String> _strings(dynamic value) => value is Iterable
    ? value.whereType<String>().where((s) => s.trim().isNotEmpty).toList() : <String>[];
  bool _matches(Map<String,dynamic> data) {
    if (_category != 'All categories' && data['category'] != _category) return false;
    final term = _search.text.trim().toLowerCase();
    if (term.isEmpty) return true;
    return [data['title'],data['description'],data['category'],data['advertType'],data['county'],data['town'],data['estate'],data['businessName']]
      .whereType<Object>().join(' ').toLowerCase().contains(term);
  }
  Future<void> _openWebsite() async {
    final ok = await launchUrl(Uri.parse(_website), mode: LaunchMode.externalApplication);
    if (!ok && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open SkyNest website.')));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('SkyNest Inventory'), actions: [
        IconButton(tooltip: 'Open marketplace website', onPressed: _openWebsite, icon: const Icon(Icons.open_in_new_rounded)),
      ]),
      body: Column(children: [
        Container(
          width: double.infinity, margin: const EdgeInsets.fromLTRB(16,10,16,14), padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topLeft,end: Alignment.bottomRight,colors:[Color(0xFF082B67),Color(0xFF1769D2),Color(0xFF103D83)]),
            borderRadius: BorderRadius.circular(22),
            boxShadow:[BoxShadow(color:const Color(0xFF155EEF).withOpacity(.2),blurRadius:20,offset:const Offset(0,8))],
          ),
          child: const Row(children:[
            Icon(Icons.storefront_rounded,color:Colors.white,size:36),SizedBox(width:14),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('Discover what is available',style:TextStyle(color:Colors.white,fontSize:17,fontWeight:FontWeight.w800)),
              SizedBox(height:4),Text('Approved adverts from the SkyNest website, in one place.',style:TextStyle(color:Color(0xFFDCEAFF),fontSize:11,height:1.4)),
            ])),
            Icon(Icons.verified_rounded,color:Colors.greenAccent,size:25),
          ]),
        ),
        Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:TextField(
          controller:_search,onChanged:(_)=>setState((){}),
          decoration:InputDecoration(hintText:'Search adverts, towns or keywords',prefixIcon:const Icon(Icons.search_rounded),
            suffixIcon:_search.text.isEmpty?null:IconButton(onPressed:(){_search.clear();setState((){});},icon:const Icon(Icons.close_rounded)),
            filled:true,fillColor:scheme.surfaceContainerHighest.withOpacity(.55),
            border:OutlineInputBorder(borderRadius:BorderRadius.circular(15),borderSide:BorderSide.none)),
        )),
        Padding(padding:const EdgeInsets.fromLTRB(16,10,16,6),child:DropdownButtonFormField<String>(
          value:_category,isExpanded:true,decoration:InputDecoration(labelText:'Category',prefixIcon:const Icon(Icons.tune_rounded),
            filled:true,fillColor:scheme.surfaceContainerHighest.withOpacity(.35),border:OutlineInputBorder(borderRadius:BorderRadius.circular(14))),
          items:_categories.map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),
          onChanged:(v)=>setState(()=>_category=v??'All categories'),
        )),
        Expanded(child:StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
          stream:_feed,
          builder:(context,snapshot){
            if(snapshot.hasError)return _InventoryMessage(icon:Icons.cloud_off_rounded,title:'Inventory is temporarily unavailable',
              message:'Check your connection. If this continues, the marketplace Firebase rules or index may need attention.',
              action:'Retry',onAction:()=>setState(_refreshFeed));
            if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
            final docs=snapshot.data!.docs.where((d)=>_matches(d.data())).toList();
            if(docs.isEmpty)return _InventoryMessage(
              icon:Icons.storefront_outlined,
              title:_search.text.isEmpty&&_category=='All categories'?'No approved adverts yet':'No matching adverts',
              message:_search.text.isEmpty&&_category=='All categories'
                ?'Website adverts appear here after the SkyNest administrator approves them.'
                :'Try another keyword or category, or explore the full website marketplace.',
              action:'Open SkyNest website',onAction:_openWebsite);
            return RefreshIndicator(
              onRefresh:()async{setState(_refreshFeed);await Future<void>.delayed(const Duration(milliseconds:400));},
              child:ListView.separated(
                physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.fromLTRB(16,8,16,24),
                itemCount:docs.length,separatorBuilder:(_,__)=>const SizedBox(height:12),
                itemBuilder:(context,index)=>_InventoryListingCard(data:docs[index].data(),onTap:()=>Navigator.of(context).push(
                  MaterialPageRoute<void>(builder:(_)=>_InventoryListingDetail(data:docs[index].data())))),
              ),
            );
          },
        )),
      ]),
    );
  }
}

class _InventoryListingCard extends StatelessWidget {
  const _InventoryListingCard({required this.data,required this.onTap});
  final Map<String,dynamic> data;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final scheme=Theme.of(context).colorScheme;
    final photos=data['photoUrls'];
    final image=photos is Iterable&&photos.isNotEmpty?photos.first.toString():null;
    final price=data['price'] is num&&(data['price'] as num)>0
      ?NumberFormat.currency(locale:'en_KE',symbol:'KSh ',decimalDigits:0).format(data['price'])
      :'Contact for price';
    final location=[data['town'],data['estate']].whereType<String>().where((s)=>s.isNotEmpty).join(' · ');
    return Card(
      clipBehavior:Clip.antiAlias,elevation:2,shadowColor:const Color(0xFF155EEF).withOpacity(.1),
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(19),side:BorderSide(color:scheme.outlineVariant.withOpacity(.55))),
      child:InkWell(onTap:onTap,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Stack(children:[
          SizedBox(height:174,width:double.infinity,child:image==null
            ?Container(color:scheme.primaryContainer,child:Icon(Icons.photo_outlined,size:48,color:scheme.primary))
            :Image.network(image,fit:BoxFit.cover,errorBuilder:(_,__,___)=>Container(color:scheme.primaryContainer,child:Icon(Icons.image_not_supported_outlined,size:42,color:scheme.primary)))),
          Positioned(top:12,left:12,child:Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),
            decoration:BoxDecoration(color:const Color(0xFF087A50),borderRadius:BorderRadius.circular(30)),
            child:const Text('APPROVED',style:TextStyle(color:Colors.white,fontSize:9,fontWeight:FontWeight.w800,letterSpacing:.7)))),
        ]),
        Padding(padding:const EdgeInsets.fromLTRB(15,13,15,15),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('${data['category']??'Advert'} · ${data['county']??'Kenya'}',style:TextStyle(color:scheme.primary,fontSize:10,fontWeight:FontWeight.w800)),
          const SizedBox(height:5),Text(data['title']?.toString()??'SkyNest advert',maxLines:2,overflow:TextOverflow.ellipsis,
            style:const TextStyle(fontSize:16,fontWeight:FontWeight.w800)),
          const SizedBox(height:5),Text(location,style:TextStyle(color:scheme.onSurfaceVariant,fontSize:11)),
          const SizedBox(height:10),Row(children:[Expanded(child:Text(price,style:TextStyle(color:scheme.primary,fontSize:15,fontWeight:FontWeight.w900))),
            const Icon(Icons.arrow_forward_rounded,size:19)]),
        ])),
      ])),
    );
  }
}

class _InventoryListingDetail extends StatelessWidget {
  const _InventoryListingDetail({required this.data});
  final Map<String,dynamic> data;
  List<String> get photos => data['photoUrls'] is Iterable ? (data['photoUrls'] as Iterable).whereType<String>().toList() : <String>[];
  List<String> get videos => data['videoUrls'] is Iterable ? (data['videoUrls'] as Iterable).whereType<String>().toList() : <String>[];

  Future<void> _contact(BuildContext context) async {
    final phone=data['contactPhone']?.toString().trim()??'';
    if(phone.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('No contact number was supplied.')));return;}
    if(!await launchUrl(Uri(scheme:'tel',path:phone))&&context.mounted){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not open the phone dialler.')));
    }
  }
  Future<void> _openVideo(BuildContext context,String url) async {
    final uri=Uri.tryParse(url);
    if(uri==null||!await launchUrl(uri,mode:LaunchMode.externalApplication)){
      if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not open this video.')));
    }
  }
  @override
  Widget build(BuildContext context) {
    final scheme=Theme.of(context).colorScheme;
    final price=data['price'] is num&&(data['price'] as num)>0
      ?NumberFormat.currency(locale:'en_KE',symbol:'KSh ',decimalDigits:0).format(data['price'])
      :'Contact for price';
    final location=[data['town'],data['county'],data['estate']].whereType<String>().where((s)=>s.isNotEmpty).join(' · ');
    return Scaffold(appBar:AppBar(title:const Text('Advert details')),body:ListView(padding:const EdgeInsets.only(bottom:28),children:[
      if(photos.isNotEmpty)SizedBox(height:260,child:PageView.builder(itemCount:photos.length,itemBuilder:(context,index)=>Image.network(photos[index],fit:BoxFit.cover,
        errorBuilder:(_,__,___)=>Container(color:scheme.surfaceContainerHighest,child:const Icon(Icons.broken_image_outlined,size:48)))))
      else Container(height:180,color:scheme.primaryContainer,child:Icon(Icons.storefront_rounded,size:56,color:scheme.primary)),
      Padding(padding:const EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('${data['category']??'Advert'} · ${data['advertType']??'Offer'}',style:TextStyle(color:scheme.primary,fontSize:11,fontWeight:FontWeight.w800)),
        const SizedBox(height:8),Text(data['title']?.toString()??'SkyNest advert',style:const TextStyle(fontSize:24,fontWeight:FontWeight.w900,height:1.15)),
        const SizedBox(height:10),Text(price,style:TextStyle(color:scheme.primary,fontSize:21,fontWeight:FontWeight.w900)),
        if(location.isNotEmpty)Padding(padding:const EdgeInsets.only(top:12),child:Row(children:[
          Icon(Icons.location_on_outlined,color:scheme.onSurfaceVariant,size:18),const SizedBox(width:5),Expanded(child:Text(location,style:TextStyle(color:scheme.onSurfaceVariant)))])),
        const SizedBox(height:22),const Text('About this advert',style:TextStyle(fontSize:16,fontWeight:FontWeight.w800)),
        const SizedBox(height:8),Text(data['description']?.toString()??'No description provided.',style:TextStyle(height:1.55,color:scheme.onSurfaceVariant)),
        if(data['businessName'] is String&&(data['businessName'] as String).isNotEmpty)...[
          const SizedBox(height:18),Text('Advertiser',style:TextStyle(color:scheme.onSurfaceVariant,fontSize:11)),Text(data['businessName'],style:const TextStyle(fontWeight:FontWeight.w700))],
        if(videos.isNotEmpty)...[
          const SizedBox(height:20),const Text('Videos',style:TextStyle(fontSize:16,fontWeight:FontWeight.w800)),
          ...videos.map((url)=>ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.play_circle_outline_rounded),
            title:const Text('Watch advert video'),trailing:const Icon(Icons.open_in_new_rounded,size:18),onTap:()=>_openVideo(context,url)))],
        const SizedBox(height:24),SizedBox(width:double.infinity,child:FilledButton.icon(
          onPressed:()=>_contact(context),icon:const Icon(Icons.call_rounded),label:const Text('Contact advertiser'),
          style:FilledButton.styleFrom(backgroundColor:const Color(0xFF087A50),foregroundColor:Colors.white,padding:const EdgeInsets.symmetric(vertical:16)))),
      ])),
    ]));
  }
}

class _InventoryMessage extends StatelessWidget {
  const _InventoryMessage({required this.icon,required this.title,required this.message,this.action,this.onAction});
  final IconData icon;final String title,message;final String? action;final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) {
    final scheme=Theme.of(context).colorScheme;
    return Center(child:Padding(padding:const EdgeInsets.all(30),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Icon(icon,size:54,color:scheme.primary),const SizedBox(height:16),
      Text(title,textAlign:TextAlign.center,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
      const SizedBox(height:8),Text(message,textAlign:TextAlign.center,style:TextStyle(color:scheme.onSurfaceVariant,height:1.45)),
      if(action!=null&&onAction!=null)...[const SizedBox(height:18),OutlinedButton.icon(onPressed:onAction,icon:const Icon(Icons.open_in_new_rounded),label:Text(action!))],
    ])));
  }
}
