#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <string>
#include <filesystem> // C++17 feature
#include <stdexcept>
namespace fs = std::filesystem;

inline size_t countSimulatorTimesteps(const std::string& filename) {
    std::ifstream file(filename);
    if (!file) throw std::runtime_error("Cannot open input CSV: " + filename);
    std::string line, value;
    while (std::getline(file, line)) {
        if (line.empty()) continue;
        std::stringstream row(line);
        std::getline(row, value, ',');
        std::getline(row, value, ',');
        size_t count = 0;
        while (std::getline(row, value, ',')) {
            if (!value.empty()) ++count;
        }
        if (count > 1) return count - 1;
    }
    throw std::runtime_error("Input CSV contains no timesteps: " + filename);
}



inline std::vector<std::vector<double>> parseSimulatorCSV(const std::string& filename) {
    std::vector<std::vector<double>> all_data;
    std::vector<std::vector<double>> grouped_data;
    std::ifstream file(filename);
    std::string line;

    if (!file.is_open()) return all_data; // Return empty if file fails

    while (std::getline(file, line)) {
        // Skip the empty rows
        if (line.empty()) continue;

        std::stringstream ss(line);
        std::string value;
        std::vector<double> raw_row;

        // Delete the first two values (gem5 outputs 2 initial and one final number that is irrelevant for ths simulation)
        std::getline(ss, value, ','); 
        std::getline(ss, value, ',');

        // 3. Collect everything else
        while (std::getline(ss, value, ',')) {
            if (!value.empty()) {
                raw_row.push_back(std::stod(value));
            }
        }

        // If we have data, pop the last entry
        if (raw_row.size() > 1) {
            raw_row.pop_back(); 
            all_data.push_back(raw_row);
        }
    }

    size_t expected_length = all_data[0].size();

    for (size_t i = 0; i < all_data.size(); ++i) {
        if (all_data[i].size() != expected_length) {
            std::cerr << "Warning: Inconsistent row length at row " << i << std::endl;
        }
    }


    std::cout << "Verification successful: All " << all_data.size() << " rows have " << expected_length << " timestamps." << std::endl;



    int totalRows = all_data.size();
    int numColumns = all_data[0].size();

// Reserve space for exactly 2048 banks to avoid reallocations
    grouped_data.reserve(2048);

// Iterate in jumps of 4
    for (int i = 0; i < totalRows; i += 4) {
        // Create a new row initialized with zeros, same length as the original columns
        std::vector<double> bank_sum(numColumns, 0.0);

        // Sum the 4 sets into this one bank row
        for (int step = 0; step < 4; ++step) {
            if (i + step < totalRows) { // Safety check
                for (int col = 0; col < numColumns; ++col) {
                    bank_sum[col] += all_data[i + step][col];
                }
            }
        }

        // Move the completed bank row into new collection
        grouped_data.push_back(std::move(bank_sum));

    }
    std::cout << "No. of timestamps" << grouped_data[0].size() << std::endl;
    return grouped_data;
}

