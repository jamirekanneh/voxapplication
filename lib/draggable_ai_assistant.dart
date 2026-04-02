import 'package:flutter/material.dart';
import 'ai_service.dart';

class DraggableAiAssistant extends StatefulWidget {
  final bool visible;
  const DraggableAiAssistant({super.key, required this.visible});

  @override
  State<DraggableAiAssistant> createState() => _DraggableAiAssistantState();
}

class _DraggableAiAssistantState extends State<DraggableAiAssistant> {
  final ValueNotifier<Offset> _position = ValueNotifier<Offset>(const Offset(20, 100));
  bool _isExpanded = false;
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _isTyping = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _position.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTap() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _isTyping = true;
      _controller.clear();
    });

    _scrollToBottom();

    try {
      final response = await AiService.helpUser(text);
      if (mounted) {
        setState(() {
          _messages.add({'role': 'assistant', 'content': response});
          _isTyping = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add({'role': 'assistant', 'content': 'Sorry, I encountered an error: $e'});
          _isTyping = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();

    final size = MediaQuery.of(context).size;

    return Stack(
      children: [
        ValueListenableBuilder<Offset>(
          valueListenable: _position,
          builder: (context, pos, child) {
            return Positioned(
              left: pos.dx,
              top: pos.dy,
              child: Material(
                type: MaterialType.transparency,
                child: RepaintBoundary(
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      _position.value += details.delta;
                      // Keep within screen bounds
                      double x = _position.value.dx.clamp(0.0, size.width - 60);
                      double y = _position.value.dy.clamp(0.0, size.height - 60);
                      _position.value = Offset(x, y);
                    },
                    child: _isExpanded ? _buildExpandedChat() : _buildAssistantBubble(),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAssistantBubble() {
    return GestureDetector(
      onTap: _onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD4B96A).withOpacity(0.4),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
          border: Border.all(color: const Color(0xFFD4B96A), width: 2),
        ),
        child: const Center(
          child: Text(
            'V',
            style: TextStyle(
              color: Color(0xFFD4B96A),
              fontSize: 28,
              fontWeight: FontWeight.w900,
              fontFamily: 'Serif',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedChat() {
    return Container(
      width: 300,
      height: 400,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
        border: Border.all(color: const Color(0xFFD4B96A).withOpacity(0.5)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Vox Assistant',
                    style: TextStyle(
                      color: Color(0xFFD4B96A),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _onTap,
                  child: const Icon(Icons.close, color: Colors.white70, size: 20),
                ),
              ],
            ),
          ),
          // Messages
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return _buildTypingIndicator();
                }
                final msg = _messages[index];
                final isUser = msg['role'] == 'user';
                return _buildMessageBubble(msg['content']!, isUser);
              },
            ),
          ),
          // Input
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Colors.black12)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Ask me anything about Vox...',
                      hintStyle: TextStyle(fontSize: 13),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send_rounded, color: Color(0xFFD4B96A)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(String content, bool isUser) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFFD4B96A) : const Color(0xFFF3F3F3),
          borderRadius: BorderRadius.circular(15).copyWith(
            bottomRight: isUser ? Radius.zero : null,
            bottomLeft: !isUser ? Radius.zero : null,
          ),
        ),
        child: Text(
          content,
          style: TextStyle(
            color: isUser ? Colors.black : Colors.black87,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F3F3),
          borderRadius: BorderRadius.circular(15).copyWith(bottomLeft: Radius.zero),
        ),
        child: const Text(
          'Typing...',
          style: TextStyle(color: Colors.black45, fontSize: 11, fontStyle: FontStyle.italic),
        ),
      ),
    );
  }
}
