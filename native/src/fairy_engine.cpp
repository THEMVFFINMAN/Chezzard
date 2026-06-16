#include "fairy_engine.h"

#include <condition_variable>
#include <iostream>
#include <streambuf>

using namespace godot;

// Fairy-Stockfish's entry point. We compile its main.cpp with -Dmain=fairy_sf_main
// (see SConstruct) so we can call the engine's full, version-correct startup +
// UCI loop without re-implementing its init sequence. It blocks until it reads
// "quit", then returns.
extern int fairy_sf_main(int argc, char *argv[]);

// ---------------------------------------------------------------------------
// Input: a blocking streambuf backed by a queue of command lines.
// The engine thread sits in std::getline(std::cin, ...) -> underflow() blocks
// here until send_command() pushes something.
// ---------------------------------------------------------------------------
class FairyInputBuf : public std::streambuf {
	std::mutex m;
	std::condition_variable cv;
	std::deque<std::string> lines;
	std::string current;

protected:
	int underflow() override {
		if (gptr() < egptr()) {
			return traits_type::to_int_type(*gptr());
		}
		std::unique_lock<std::mutex> lk(m);
		cv.wait(lk, [&] { return !lines.empty(); });
		current = lines.front();
		lines.pop_front();
		lk.unlock();
		current.push_back('\n'); // getline needs the delimiter
		setg(&current[0], &current[0], &current[0] + current.size());
		return traits_type::to_int_type(*gptr());
	}

public:
	void push(const std::string &s) {
		{
			std::lock_guard<std::mutex> lk(m);
			lines.push_back(s);
		}
		cv.notify_one();
	}
};

// ---------------------------------------------------------------------------
// Output: a streambuf that splits the engine's std::cout into lines and hands
// each completed line to the owning FairyEngine.
// ---------------------------------------------------------------------------
class FairyOutputBuf : public std::streambuf {
	godot::FairyEngine *owner;

public:
	explicit FairyOutputBuf(godot::FairyEngine *o) :
			owner(o) {}

protected:
	int overflow(int c) override {
		// Per-thread line accumulation: the engine's search threads can write to
		// std::cout concurrently, so each thread builds its own line and only
		// hands a complete line to the (mutex-guarded) output queue. A single
		// shared buffer would let concurrent writers corrupt or interleave a line.
		thread_local std::string line;
		if (c == traits_type::eof()) {
			return c;
		}
		char ch = traits_type::to_char_type(c);
		if (ch == '\n') {
			owner->push_output_line(line);
			line.clear();
		} else if (ch != '\r') {
			line.push_back(ch);
		}
		return c;
	}

	std::streamsize xsputn(const char *s, std::streamsize n) override {
		for (std::streamsize i = 0; i < n; ++i) {
			overflow(traits_type::to_int_type(s[i]));
		}
		return n;
	}
};

// ---------------------------------------------------------------------------
// FairyEngine
// ---------------------------------------------------------------------------
void FairyEngine::_bind_methods() {
	ClassDB::bind_method(D_METHOD("start"), &FairyEngine::start);
	ClassDB::bind_method(D_METHOD("send_command", "command"), &FairyEngine::send_command);
	ClassDB::bind_method(D_METHOD("stop"), &FairyEngine::stop);

	ADD_SIGNAL(MethodInfo("output_received", PropertyInfo(Variant::STRING, "line")));
}

FairyEngine::FairyEngine() {}

FairyEngine::~FairyEngine() {
	stop();
}

void FairyEngine::start() {
	if (running.load()) {
		return;
	}
	input_buf = new FairyInputBuf();
	output_buf = new FairyOutputBuf(this);
	running.store(true);
	engine_thread = std::thread(&FairyEngine::engine_main, this);
}

void FairyEngine::engine_main() {
	// Redirect process-wide stdio to our queues for the lifetime of the loop.
	// Search threads also print through std::cout (via sync_cout), so they are
	// covered too.
	saved_cin = std::cin.rdbuf(input_buf);
	saved_cout = std::cout.rdbuf(output_buf);

	char arg0[] = "fairy";
	char *argv[] = { arg0, nullptr };
	fairy_sf_main(1, argv); // blocks until "quit"
}

void FairyEngine::send_command(const String &command) {
	if (!input_buf) {
		return;
	}
	input_buf->push(std::string(command.utf8().get_data()));
}

void FairyEngine::push_output_line(const std::string &s) {
	std::lock_guard<std::mutex> lk(out_mutex);
	out_lines.push_back(String::utf8(s.c_str()));
}

void FairyEngine::stop() {
	if (!running.load()) {
		return;
	}
	if (input_buf) {
		input_buf->push("quit"); // breaks UCI::loop -> fairy_sf_main returns
	}
	if (engine_thread.joinable()) {
		engine_thread.join();
	}
	running.store(false);

	if (saved_cin) {
		std::cin.rdbuf(saved_cin);
		saved_cin = nullptr;
	}
	if (saved_cout) {
		std::cout.rdbuf(saved_cout);
		saved_cout = nullptr;
	}

	delete input_buf;
	input_buf = nullptr;
	delete output_buf;
	output_buf = nullptr;
}

void FairyEngine::_process(double) {
	// Drain on the main thread and emit signals there (Godot signals are not
	// safe to emit from arbitrary threads).
	std::deque<String> local;
	{
		std::lock_guard<std::mutex> lk(out_mutex);
		local.swap(out_lines);
	}
	for (const String &l : local) {
		emit_signal("output_received", l);
	}
}
