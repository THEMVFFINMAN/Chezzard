#ifndef FAIRY_ENGINE_H
#define FAIRY_ENGINE_H

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <atomic>
#include <deque>
#include <mutex>
#include <string>
#include <thread>

// Defined in fairy_engine.cpp. These are std::streambuf subclasses that bridge
// the engine's std::cin / std::cout to our in-memory queues, so we never spawn
// a subprocess or touch real stdio.
class FairyInputBuf;
class FairyOutputBuf;

namespace godot {

// Thin GDExtension wrapper around an embedded Fairy-Stockfish engine.
//
// Instead of running stockfish.exe as a child process and piping UCI text over
// stdin/stdout (which is impossible on iOS and unreliable on Android), the
// engine is compiled INTO the app. Its UCI loop runs on a background thread; we
// feed it commands through send_command() and surface every line it prints via
// the `output_received` signal (emitted on the main thread from _process()).
//
// NOTE: Fairy-Stockfish keeps global engine state, so only ONE instance may be
// alive at a time. Create one, start() it, and stop() it on shutdown.
class FairyEngine : public Node {
	GDCLASS(FairyEngine, Node)

private:
	std::thread engine_thread;
	std::atomic<bool> running{ false };

	// Output lines waiting to be drained on the main thread.
	std::mutex out_mutex;
	std::deque<String> out_lines;

	FairyInputBuf *input_buf = nullptr;
	FairyOutputBuf *output_buf = nullptr;

	// Saved std::cin / std::cout buffers so we can restore them on stop().
	std::streambuf *saved_cin = nullptr;
	std::streambuf *saved_cout = nullptr;

	void engine_main();

protected:
	static void _bind_methods();

public:
	FairyEngine();
	~FairyEngine();

	// Boot the engine on its own thread. No-op if already running.
	void start();
	// Queue a UCI command (newline is added automatically).
	void send_command(const String &command);
	// Send "quit", join the thread, and restore stdio. Safe to call twice.
	void stop();

	// Called by FairyOutputBuf from the engine/search threads.
	void push_output_line(const std::string &line);

	void _process(double delta) override;
};

} // namespace godot

#endif // FAIRY_ENGINE_H
