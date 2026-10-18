#include <vector>
#include <cstdint>
#include <cmath>
#include <iostream>
#include <numeric>
#include <filesystem>
#include <array>
#include <bit>
#include "Read_sim_stats.h"
#include "STTRAM_Power_Model.h"
#include "STTRAM_Thermal_Model.h"

int main(int argc, char* argv[]) {
    std::cout << "==================================================\n";
    std::cout << "         STT-RAM Thermal Simulation Engine\n";
    std::cout << "==================================================\n\n";

    if (argc > 3) {
        std::cerr << "Usage: " << argv[0] << " [path/to/file.csv] [results_folder]\n";
        return 1;
    }

    std::string csv_file_path = (argc >= 2) ? argv[1] : "data/stream.csv";
    std::string results_folder = (argc == 3) ? argv[2] : "Results";

    std::cout << "Attempting to load file: \n" << csv_file_path << "\n\n";

    // Initialize an instance of ThermalModel
    ThermalModel stt_ram_cache;

    // Load the benchmark data 
    try {
        stt_ram_cache.loadSimData(csv_file_path);
        std::cout << "[SUCCESS] CSV Data loaded into vector.\n";
    } catch (const std::exception& e) {
        // If the path is wrong, catch it here instead of crashing
        std::cerr << "[ERROR] Could not load CSV: " << e.what() << "\n";
        std::cerr << "Check the path to the file is written correctly\n";
        return 1; 
    }

    std::cout << "Starting Thermal Simulation...\n\n";

    auto start_time = std::chrono::high_resolution_clock::now();

    // Run the simulation
    if (!stt_ram_cache.runFullSimulation(results_folder)) {
        std::cerr << "[ERROR] Simulation failed.\n";
        return 1;
    }

    // Calculate simulation time
    auto end_time = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> elapsed = end_time - start_time;

    std::cout << "\n======================================================\n";
    std::cout << "Simulation Complete!\n";
    std::cout << "Total execution time: " << elapsed.count() << " seconds.\n";
    std::cout << "========================================================\n";

    return 0;
}
