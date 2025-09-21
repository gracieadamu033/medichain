# MediChain - Medical Supply Chain Authentication

## Overview

MediChain is a blockchain-based medical supply chain tracking system built on Stacks using Clarity smart contracts. The system ensures authenticity and traceability of medicines throughout the entire supply chain process.

## Problem Statement

The pharmaceutical industry faces significant challenges with counterfeit medicines, supply chain opacity, and lack of traceability. According to the World Health Organization, approximately 10% of medical products in low and middle-income countries are substandard or falsified.

## Solution

MediChain provides a decentralized solution to track medicines from manufacturing to end consumer, ensuring:

- **Authenticity Verification**: Each medicine batch is registered with a unique identifier
- **Supply Chain Transparency**: Complete tracking of medicine movement through distributors and pharmacies
- **Immutable Records**: Blockchain-based records prevent tampering and provide audit trails
- **Real-time Verification**: Instant verification of medicine authenticity by scanning QR codes

## Key Features

### Medicine Registration
- Manufacturers can register new medicine batches
- Each batch receives a unique blockchain-based identifier
- Detailed information including batch number, expiry date, and manufacturer details

### Supply Chain Tracking
- Track medicine movement through multiple supply chain participants
- Record transfers between manufacturers, distributors, and pharmacies
- Maintain chain of custody with timestamp verification

### Authenticity Verification
- Quick verification of medicine authenticity using batch IDs
- Check current ownership and supply chain history
- Verify expiry dates and batch information

### Access Control
- Role-based access control for different supply chain participants
- Secure registration process for manufacturers, distributors, and pharmacies
- Authorization checks for all critical operations

## Technical Architecture

The system consists of two main smart contracts:

1. **Medicine Registry Contract**: Manages medicine batch registration and core data
2. **Supply Chain Tracker Contract**: Handles medicine transfers and ownership tracking

## Smart Contract Functions

### Medicine Registry
- `register-medicine`: Register new medicine batches
- `get-medicine-info`: Retrieve medicine batch details
- `verify-authenticity`: Check if medicine batch is genuine
- `update-expiry-status`: Mark medicines as expired

### Supply Chain Tracker
- `transfer-medicine`: Transfer medicine ownership
- `add-supply-chain-participant`: Register new participants
- `get-medicine-history`: Retrieve complete supply chain history
- `verify-current-owner`: Check current medicine ownership

## Getting Started

### Prerequisites
- Clarinet CLI installed
- Node.js and npm
- Git

### Installation

1. Clone the repository
2. Install dependencies: `npm install`
3. Run contract checks: `clarinet check`
4. Run tests: `npm test`

## Usage

### Registering a Medicine Batch
```clarity
(contract-call? .medicine-registry register-medicine 
  "BATCH001" 
  "Aspirin" 
  "Generic Pharma" 
  u1000 
  u1735689600) ;; Expiry timestamp
```

### Transferring Medicine
```clarity
(contract-call? .supply-chain-tracker transfer-medicine 
  "BATCH001" 
  'SP2DISTRIBUTOR...)
```

### Verifying Authenticity
```clarity
(contract-call? .medicine-registry verify-authenticity "BATCH001")
```

## Benefits

- **Reduced Counterfeiting**: Immutable blockchain records prevent fake medicines
- **Enhanced Trust**: Transparent supply chain builds consumer confidence
- **Regulatory Compliance**: Comprehensive audit trails support regulatory requirements
- **Cost Efficiency**: Reduced costs from counterfeit-related recalls and liability
- **Patient Safety**: Ensures patients receive genuine, safe medications

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests and ensure contracts pass validation
5. Submit a pull request

## License

This project is licensed under the MIT License.

## Contact

For questions or support, please reach out through GitHub issues.
