
# JMeter JDBC Query Performance Test Plans and wrapper scripts

This repository contains JMeter test plans for evaluating query performance, developed by E6Data.
This repo also has some wrapper scripts that can run the Jmeter tests by taking user inputs interactively from command prompt.

## Prerequisites

### Java 17 should be installed

## Test properties files

The test plans are created to run in different environments using property files as below :
- `connection.properties` - Manages JDBC database connection parameters
- `test.properties` - Controls test behavior settings


#### Steps to install java - Option 1 using package manager

**Amazon Linux 2:**
```bash
sudo amazon-linux-extras enable corretto8
sudo yum install java-17-amazon-corretto-devel
```

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install openjdk-17-jdk
```

#### Steps to install java - Option 2: Manual Installation
```bash
wget https://download.java.net/java/GA/jdk17.0.2/dfd4a8d0985749f896bed50d7138ee7f/8/GPL/openjdk-17.0.2_linux-x64_bin.tar.gz
tar -xvf openjdk-17.0.2_linux-x64_bin.tar.gz
sudo mv jdk-17.0.2 /usr/local/
```

#### Verification of java version:
```bash
java -version
export JAVA_HOME=/usr/lib/jvm/java-17-amazon-corretto.aarch64
echo "export JAVA_HOME=/usr/lib/jvm/java-17-amazon-corretto.aarch64" >> ~/.bashrc
source ~/.bashrc
```

### jq Installation

**Amazon Linux:**
```bash
# For Amazon Linux 2:
sudo yum install -y jq

# For Amazon Linux 2023:
sudo dnf install -y jq

# Verify:
jq --version
```

# Running Tests using standard jmeter CLI command.
```bash
$JMETER_BIN/jmeter -n -t "$TEST_PLAN" -l "$REPORT_PATH/results.jtl" -q "$TEST_PROPERTIES" -q "$CONNECTION_PROPERTIES" -JQUERY_PATH=$QUERIES_FILE
```

## Example - Run Jmeter in GUI mode:
```bash
./apache-jmeter-5.6.3/bin/jmeter -t Test-Plans/Test-Plan-Maintain-static-concurrency.jmx -q connection_properties/sample_connection.properties -q test_properties/sample_test.properties
```
## Example - Run Jmeter in Non GUI mode:
```bash
./apache-jmeter-5.6.3/bin/jmeter -n -t Test-Plans/Test-Plan-Maintain-static-concurrency.jmx -q connection_properties/sample_connection.properties  -q test_properties/sample_test.properties
```


# Running Tests interactively using the wrapper script
Execute the interactive test runner:
```bash
./run_jmeter_tests_interactive.sh
```

## File Structure

```
.
├── README.md
├── apache-jmeter-5.6.3
├── connection.properties
    └── [Connection properties file *.properties]
    └── [sample_connection.properties ]
├── data_files
    └── [CSV Queries file *.csv]
    └── [sample_queries.csv ]
├── metadata_files - optional
    └── [sample_metadata.txt - Optional required only to copy data to s3 or storage for keeping track of runs ]
├── test.properties
    └── [Test properties file *.properties]
    └── [sample_test.properties ]
├── Scripts
    ├── run_jmeter_tests_interactive.sh
└── Test-Plans
    └── [JMX test files]
    └── [Test-Plan-Constant-QPM-On-Arrivals.jmx - To fire queries per minute using QPM in test.properties]
    └── [Test-Plan-Constant-QPS-On-Arrivals.jmx - To fire queries per sec using QPs in test.properties]
    └── [Test-Plan-Fire-QPM-with-load-profile.jmx - To fire queries per minute using load profile file in test.properties]
    └── [Test-Plan-Fire-QPS-with-load-profile.jmx - To fire queries per minute using load profile file in test.properties]
    └── [Test-Plan-Maintain-static-concurrency.jmx - To maintain fixed load / concurrency using concurrency in test.properties]
    └── [Test-Plan-Maintain-variable-concurrency-with-load-profile.jmx - To maintain load/concurrency using load profile file in test.properties]


```

## Property Files

Sample configurations:

**sample_e6_connection.properties:**
```
# JDBC Jmeter connection properties

#Change below properties to connect to your target machine via JDBC
HOSTNAME=
PORT=80
DATABASE=
CATALOG=

USER=
PASSWORD=

#Change below for the JDBC connection URL of your target machine
CONNECTION_STRING=

#Change below to your JDBC Driver class
DRIVER_CLASS=io.e6.jdbc.driver.E6Driver

```

**sample_e6_test.properties:**
```
# E6 Jmeter Test properties

JMETER_HOME=

#Change below for Report directory path. Reports will be written in this directory
REPORT_PATH=reports

COPY_TO_S3=false
S3_REPORT_PATH=s3://

#Change below for concurrency based test plan which will maintain this concurrency. This applicable only for concurrency based plan
CONCURRENT_QUERY_COUNT=2

#Change below if u want to add RAMP_TIME(min) and RAMP_UP_STEPS (counts) to reach target concurrency 
RAMP_UP_TIME=1
RAMP_UP_STEPS=1

#Total time to run the test in minutes i.e hold the load. This is after ramp up time 
HOLD_PERIOD=300

#Change below for QPM based Test Plan which will fire below number of queries per minute. This is applicable only for QPM based test Plan
QPM=10

#Change below for QPS based Test Plan which will fire below number of queries per sec. This is applicable only for QPs based test Plan
QPS=1

#Change below for load_profile based Test Plan. This will be applicable only if u select the load profile Test Plan
LOAD_PROFILE=test_properties/load_profile.csv

#To select queries from the CSV in Random Order set below to true
RANDOM_ORDER=true

# Set below variable to true if you want to Repeat the queries in the CSV, this essentially means queries will repeat till the test duration 
RECYCLE_ON_EOF=false

#Change below to the absolute path of your query file
QUERY_PATH=../data_files/Benchmark_TPCDS-51-queries_without_bootstrap.csv

```

## Important Note

DO NOT PUT YOUR SENSITIVE LOGIN/CREDENTIALS OR ANY SUCH SENSITIVE INFO NEITHER IN PROPERTIES/JMETER TEST PLAN OR ANY SUCH FILE.
CHECK THE .gitignore file as we avoid some sensitive info to be checked in.

## DISCLAIMER
This is just a sample collection that can be used for jmeter testing, so please check the parameters and use proper reasonable values as improper setting can overload/damage the system
Do not test directly on some production system without verification as the system can be overloaded if proper values are not set.


## STEPS TO RUN USING WRAPPER SCRIPT - OPTIONAL
# Install Java 17 - If not installed
```
sudo yum install java-17-amazon-corretto -y
java -version
echo 'export JAVA_HOME=/usr/lib/jvm/java-17-amazon-corretto' >> ~/.bashrc
echo 'export PATH=$JAVA_HOME/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
echo $JAVA_HOME
ls -l $JAVA_HOME
java -version
```

# Install git - If not installed
```
sudo yum install git
```

# Clone the repo
```
git clone https://github.com/george-pc/jmeter-jdbc-test-plans.git
```

# change to the cloned directory
```
cd jmeter-jdbc-test-plans/
```

# create a reports directory if not exists
```
mkdir reports
```

# verify the contents
ls -lrt

# Create/Update the connection details in the connection.properties file
```
cd connection_properties
cp connection.properties.template YOUR_CONNECTION_PROPERTIES_FILENAME.properties
cd ..
```

Use vi or any editor to open above created file and enter the connection details, Jmeter test will use this to connect to the target server

# Create/Update the test configuration details and paths in the test.properties file 
```
cd test_properties/
cp test.properties.template YOUR_TEST_PROPERTIES_FILENAME.properties
cd ..
```
Use vi or any editor to open above created file  and enter the details

# Run the interactive wrapper script to launch the jmeter run and enter the  values from the prompt
```
./run_jmeter_tests_interactive.sh
```
