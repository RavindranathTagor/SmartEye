import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: "apiKeys.env");

  runApp(
    MaterialApp(
      theme: ThemeData.dark(),
      home: TakePictureScreen(),
    ),
  );
}

class TakePictureScreen extends StatefulWidget {
  const TakePictureScreen({super.key});

  @override
  TakePictureScreenState createState() => TakePictureScreenState();
}

class TakePictureScreenState extends State<TakePictureScreen> {
  FlutterTts flutterTts = FlutterTts();
  String display = '';
  SpeechToText speechToText = SpeechToText();
  bool speechEnabled = false;
  String transcript = '';
  bool isBusy = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    speechEnabled = await speechToText.initialize();
    setState(() {});
  }

  Future<void> _startListening() async {
    if (speechEnabled) {
      await speechToText.listen(onResult: _onSpeechResult);
    }
  }

  Future<void> _stopListening() async {
    if (speechEnabled) {
      await speechToText.stop();
      setState(() {});
      await Future.delayed(const Duration(seconds: 1));

      isBusy = true;
      try {
        switch (transcript.toLowerCase()) {
          case 'describe':
            speak('describe');
            await describeScene();
            break;
          case 'product':
            speak('product');
            await readBarcode();
            break;
          default:
            speak('chatbot');
            await askChatBot(transcript);
        }
      } catch (e) {
        print('Error in _stopListening: $e');
        speak('An error occurred. Please try again.');
      }
      isBusy = false;
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      transcript = result.recognizedWords;
    });
  }

  Future<void> speak(String script) async {
    setState(() {
      display = script;
    });
    await flutterTts.speak(script);
  }



  Future<String> barcodeLookup(String code) async {
  final barcodeKey = dotenv.env['barcode'];
  if (barcodeKey == null) {
    print('API Key is not set.');
    return 'API Key is not set.';
  }

  final Uri apiUri = Uri.parse(
      'https://api.barcodelookup.com/v3/products?barcode=$code&formatted=y&key=$barcodeKey');

  print('Request URL: $apiUri');  //Debugging line

  var response = await http.get(apiUri, headers: {'Accept': 'application/json'});

  print('Status Code: ${response.statusCode}');
  print('Headers: ${response.headers}');
  print('Response body: ${response.body}');  // Debugging line

  if (response.statusCode == 200) {
    Map<String, dynamic> jsonResponse = json.decode(response.body);
    print('JSON Response: $jsonResponse');  // Debugging line
    if (jsonResponse['products'] != null && jsonResponse['products'].isNotEmpty) {
      return jsonResponse['products'][0]['title'];
    } else {
      return 'Product not found';
    }
  } else {
    return 'Information not found';
  }
}


  Future<dynamic> sendClarifaiRequest(
      dynamic content, String workflowId) async {
    final clarifaiKey = dotenv.env['clarifai'];
    var headers = {
      'Authorization': 'Key $clarifaiKey',
      'Content-Type': 'application/json',
    };
    var request = http.Request(
      'POST',
      Uri.parse(
          'https://api.clarifai.com/v2/users/ravindranath/apps/VisualAssit/workflows/$workflowId/results'),
    );

    Map body;
    if (workflowId == 'chatbot') {
      body = {
        "inputs": [
          {
            "data": {
              "text": {
                "raw": '''<s>
                  <<SYS>> You are a virtual assistant. Your response must be below 50 words and it should be in kannada language <</SYS>>
                  [INST] $content [/INST]'''
              }
            }
          }
        ]
      };
    } else {
      body = {
        "inputs": [
          {
            "data": {
              "image": {"base64": content}
            }
          }
        ]
      };
    }

    request.body = json.encode(body);
    request.headers.addAll(headers);

    speak('loading');
    http.StreamedResponse response = await request.send();

    if (response.statusCode == 200) {
      final jsonString = await response.stream.bytesToString();
      Map<String, dynamic> jsonMap = json.decode(jsonString);
      return jsonMap['results'][0]['outputs'][0]['data'];
    } else {
      final errorString = await response.stream.bytesToString();
      print('Error response: $errorString');
      speak('Request failed.');
      return null;
    }
  }

  Future<void> describeScene() async {
    try {
      
      final response =
          await sendClarifaiRequest(base64Encode(imageBytes), 'describe');

      if (response is Map<String, dynamic> && response.containsKey('text')) {
        final description = response['text']['raw'];
        speak(description);
      } else {
        speak('Failed to describe scene.');
      }
    } catch (e) {
      print('Error in describeScene: $e');
      speak('Failed to describe scene.');
    }
  }


  Future<void> readBarcode() async {
    try {
      
      final response = await sendClarifaiRequest(base64Encode(imageBytes), 'barcode-operator');

      if (response is Map<String, dynamic> && response.containsKey('regions')) {
        final results = response['regions'];
        if (results != null) {
          int noOfBarcodes = results.length;
          if (noOfBarcodes > 1) {
            speak('$noOfBarcodes barcodes detected');
            List<String> descriptions = [];
            for (int i = 0; i < noOfBarcodes; i++) {
              final code = results[i]['data']['text']['raw'];
              final productDesc = await barcodeLookup(code);
              descriptions.add('Barcode ${i + 1}: $productDesc');
            }
            speak(descriptions.join('; '));
          } else {
            final code = results[0]['data']['text']['raw'];
            final productDesc = await barcodeLookup(code);
            speak(productDesc);
          }
        } else {
          speak('No barcode detected.');
        }
      } else {
        speak('Failed to read barcode.');
      }
    } catch (e) {
      print('Error in readBarcode: $e');
      speak('Failed to read barcode.');
    }
  }


  Future<void> askChatBot(String content) async {
    try {
      final response = await sendClarifaiRequest(content, 'chatbot');

      if (response is Map<String, dynamic> && response.containsKey('text')) {
        final chatResponse = response['text']['raw'];
        speak(chatResponse);
      } else {
        speak('Failed to get a response from chatbot.');
      }
    } catch (e) {
      print('Error in askChatBot: $e');
      speak('Failed to get a response from chatbot.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visual Assist'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Text(
                'Camera feed will be simulated.',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ),
          if (isBusy)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              display,
              style: TextStyle(fontSize: 18),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              onPressed: () {
                if (isBusy) return;
                _startListening();
              },
              child: const Text('Start Listening'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              onPressed: () {
                if (isBusy) return;
                _stopListening();
              },
              child: const Text('Stop Listening'),
            ),
          ),
        ],
      ),
    );
  }
}