const APIKEY: &str = "IB1-APIKEYHERE";
const PLATFORM: &str = "roblox";
const AGGRESSIVEOPTIMIZATIONS: &str = "0";
const INTENSEVMSCRAMBLING: &str = "false";
const ENABLEVMCOMPRESSION: &str = "false";
const MAXWAIT: u64 = 240;
const RETRYDELAY: u64 = 5;
const MAXFAILS: u64 = 3;

use anyhow::{Ok, Result};
use reqwest::Url;
use reqwest::blocking::Client;
use serde_json;
use std::fs;
use std::thread;
use std::time::Duration;

fn main() -> Result<()> {
    let url = Url::parse_with_params(
        "https://ironbrew1.com/obfuscate",
        &[
            ("platform", PLATFORM),
            ("aggressiveOptimizations", AGGRESSIVEOPTIMIZATIONS),
            ("intenseVmScrambling", INTENSEVMSCRAMBLING),
            ("enableVmCompression", ENABLEVMCOMPRESSION),
        ],
    )?;

    let response = Client::new()
        .post(url)
        .header("Key", APIKEY)
        .body(fs::read_to_string("input.lua").expect("Unable to read input file"))
        .send()?;

    if !response.status().is_success() {
        println!("Obfuscation failed with status: {}", response.status());
        return Ok(());
    }

    let t: serde_json::Value =
        serde_json::from_str(&response.text()?).expect("Unable to decode JSON");

    println!("Obfuscation started with GUID: {}", t["uploadGuid"]);

    let mut elapsedtime = 0;
    let mut failcount = 0;
    let mut waittime = 0;

    let joined = Url::parse("https://ironbrew1.com").unwrap().join(t["statusUrl"].as_str().unwrap())?;

    loop {
        waittime += RETRYDELAY;
        thread::sleep(Duration::from_secs(waittime));
        elapsedtime += waittime;

        let response = Client::new()
            .get(joined.clone())
            .header("Key", APIKEY)
            .send()?;

        if !response.status().is_success() { println!("Queue check failed with status: {}", response.status()); failcount += 1; continue; }

        let rsp: serde_json::Value =
            serde_json::from_str(&response.text()?).expect("Unable to decode JSON");

        if rsp["status"] == "completed" {
            println!("Obfuscation completed in {} seconds", elapsedtime);
            let response = Client::new()
            .get(Url::parse("https://ironbrew1.com").unwrap().join(rsp["downloadUrl"].as_str().unwrap())?)
            .header("Key", APIKEY)
            .send()?;
        fs::write("output.lua", response.text().unwrap())?;
            break;
        } else if rsp["status"] == "failed" || failcount >= MAXFAILS || elapsedtime >= MAXWAIT {
            println!("Obfuscation failed (fails: {} | status: {} | elapsed time: {})", failcount, rsp["status"], elapsedtime);
            break;
        }

        println!("Obfuscation is still in progress. Elapsed time: {} seconds. Checking again in {} seconds.", elapsedtime, RETRYDELAY + waittime);
    }

    Ok(())
}
