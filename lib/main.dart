import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';

void main() async {
  await dotenv.load(fileName: ".env");
  runApp(const CreativeAIApp());
}

class CreativeAIApp extends StatelessWidget {
  const CreativeAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI Story Creator',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigoAccent,
          brightness: Brightness.light,
        ),
        textTheme: GoogleFonts.poppinsTextTheme(),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _promptController = TextEditingController();
  String _imagePrompt = '';
  String _streamingResponse = '';
  bool _isLoading = false;
  String? _generatedImageUrl;

  Future<void> _generateStoryWithStream() async {
    setState(() {
      _isLoading = true;
      _streamingResponse = '';
      _imagePrompt = '';
      _generatedImageUrl = null;
    });

    try {
      final client = http.Client();
      final request = http.Request(
        'POST',
        Uri.parse('https://api.together.xyz/v1/chat/completions'),
      );
      
      request.headers.addAll({
        'Authorization': 'Bearer ${dotenv.env['TOGETHER_API_KEY']}',
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      });

      request.body = jsonEncode({
        'model': 'meta-llama/Meta-Llama-3-8B-Instruct-Turbo',
        'messages': [
          {'role': 'system', 'content': 'You are a creative storyteller who writes engaging short stories.'},
          {'role': 'user', 'content': 'Write a creative short story based on: ${_promptController.text}'},
        ],
        'stream': true,
      });

      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Failed to generate story');
      }

      String fullResponse = '';
      await for (final chunk in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (chunk.startsWith('data: ')) {
          final data = chunk.substring(6);
          if (data == '[DONE]') break;

          try {
            final jsonData = jsonDecode(data);
            final content = jsonData['choices'][0]['delta']['content'] ?? '';
            setState(() {
              fullResponse += content;
              _streamingResponse = fullResponse;
            });
          } catch (e) {
            print('Error parsing stream: $e');
          }
        }
      }

      final imagePromptResponse = await http.post(
        Uri.parse('https://api.together.xyz/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer ${dotenv.env['TOGETHER_API_KEY']}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'meta-llama/Meta-Llama-3-8B-Instruct-Turbo',
          'messages': [
            {'role': 'user', 'content': 'Generate a detailed image prompt for this story: $fullResponse'},
          ],
          'stream': false,
        }),
      );

      if (imagePromptResponse.statusCode == 200) {
        final jsonResponse = jsonDecode(imagePromptResponse.body);
        setState(() {
          _imagePrompt = jsonResponse['choices'][0]['message']['content'];
        });
      }
    } catch (e) {
      setState(() => _streamingResponse = 'Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _generateImage() async {
    if (_imagePrompt.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('https://api.together.xyz/v1/images/generations'),
        headers: {
          'accept': 'application/json',
          'authorization': 'Bearer ${dotenv.env['TOGETHER_API_KEY']}',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'model': 'black-forest-labs/FLUX.1-schnell-Free',
          'prompt': _imagePrompt,
          'steps': 3,
          'n': 1,
          'height': 1024,
          'width': 1024,
          'response_format': 'url',
        }),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        if (jsonResponse['data'] != null && 
            jsonResponse['data'] is List && 
            jsonResponse['data'].isNotEmpty) {
          setState(() {
            _generatedImageUrl = jsonResponse['data'][0]['url'];
          });
        }
      }
    } catch (e) {
      print('Error generating image: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.large(
            title: Text('AI Story Creator'),
            centerTitle: true,
            floating: true,
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _promptController,
                          decoration: InputDecoration(
                            labelText: 'Enter your story idea',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                          ),
                          maxLines: 3,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isLoading ? null : _generateStoryWithStream,
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.all(16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: _isLoading 
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.auto_stories),
                                label: const Text('Generate Story'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _imagePrompt.isEmpty || _isLoading ? null : _generateImage,
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.all(16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: const Icon(Icons.image),
                                label: const Text('Generate Image'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (_streamingResponse.isNotEmpty) ...[
                  Card(
                    elevation: 4,
                    margin: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.auto_stories),
                              const SizedBox(width: 8),
                              Text(
                                'Generated Story',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                          const Divider(),
                          Text(_streamingResponse),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_imagePrompt.isNotEmpty) ...[
                  Card(
                    elevation: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.brush),
                              const SizedBox(width: 8),
                              Text(
                                'Image Prompt',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                          const Divider(),
                          Text(_imagePrompt),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_generatedImageUrl != null) ...[
                  Card(
                    elevation: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const Icon(Icons.image),
                              const SizedBox(width: 8),
                              Text(
                                'Generated Image',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                        ),
                        const Divider(),
                        ClipRRect(
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(16),
                            bottomRight: Radius.circular(16),
                          ),
                          child: Image.network(
                            _generatedImageUrl!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 300,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return SizedBox(
                                height: 300,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    value: loadingProgress.expectedTotalBytes != null
                                        ? loadingProgress.cumulativeBytesLoaded /
                                            loadingProgress.expectedTotalBytes!
                                        : null,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return const SizedBox(
                                height: 300,
                                child: Center(
                                  child: Icon(Icons.error_outline, size: 50),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }
}