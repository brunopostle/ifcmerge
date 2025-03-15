use std::collections::{HashMap, HashSet};
use std::env;
use std::fs::File;
use std::io::{BufRead, BufReader, Write};
use std::process;
use chrono::Local;
use regex::Regex;

#[derive(Debug)]
struct Ifc {
    headers: Vec<String>,
    file: HashMap<usize, String>,
    added: HashSet<usize>,
    deleted: HashSet<usize>,
    modified: HashSet<usize>,
}

impl Ifc {
    fn new() -> Self {
        Ifc {
            headers: Vec::new(),
            file: HashMap::new(),
            added: HashSet::new(),
            deleted: HashSet::new(),
            modified: HashSet::new(),
        }
    }

    fn load(&mut self, path: &str) -> std::io::Result<()> {
        let file = File::open(path)?;
        let reader = BufReader::new(file);

        let entity_regex = Regex::new(r"^#([0-9]+)=(.*);").unwrap();
        let comment_regex = Regex::new(r"/\*.*\*/").unwrap();

        for line in reader.lines() {
            let line = line?;
            if let Some(caps) = entity_regex.captures(&line) {
                let id = caps[1].parse::<usize>().unwrap();
                let content = caps[2].to_string();
                self.file.insert(id, content);
            } else if comment_regex.is_match(&line) {
                // Discard comments
            } else {
                self.headers.push(line);
            }
        }
        Ok(())
    }

    fn write(&self, path: &str) -> std::io::Result<()> {
        let mut file = File::create(path)?;
        let now = Local::now();
        let now_str = now.format("%Y-%m-%dT%H:%M:%S%z").to_string();
        let now_formatted = format!("{}", &now_str[0..now_str.len()-2]) + ":" + &now_str[now_str.len()-2..];

        let datetime_regex = Regex::new(r"....-..-..[T]..:..:..[\+\-]..:..").unwrap();
        
        for line in &self.headers {
            let mut line_to_write = line.clone();
            if line.starts_with("FILE_NAME") {
                line_to_write = datetime_regex.replace(&line, &now_formatted).to_string();
            }
            writeln!(file, "{}", line_to_write)?;
            
            if line.starts_with("DATA;") {
                let mut ids: Vec<usize> = self.file.keys().cloned().collect();
                ids.sort();
                
                for id in ids {
                    if let Some(content) = self.file.get(&id) {
                        writeln!(file, "#{0}={1};", id, content)?;
                    }
                }
            }
        }
        Ok(())
    }

    fn compare(&mut self, other: &Ifc) {
        self.added.clear();
        self.modified.clear();
        self.deleted.clear();
        
        for id in self.file_ids() {
            if !other.file.contains_key(&id) {
                self.added.insert(id);
            } else if self.file.get(&id) != other.file.get(&id) {
                self.modified.insert(id);
            }
        }
        
        for id in other.file_ids() {
            if !self.file.contains_key(&id) {
                self.deleted.insert(id);
            }
        }
    }

    fn last(&self) -> usize {
        let mut ids = self.file_ids();
        ids.sort();
        *ids.last().unwrap_or(&0)
    }

    fn file_ids(&self) -> Vec<usize> {
        let mut ids: Vec<usize> = self.file.keys().cloned().collect();
        ids.sort();
        ids
    }

    fn added_ids(&self) -> Vec<usize> {
        let mut ids: Vec<usize> = self.added.iter().cloned().collect();
        ids.sort();
        ids
    }

    fn modified_ids(&self) -> Vec<usize> {
        let mut ids: Vec<usize> = self.modified.iter().cloned().collect();
        ids.sort();
        ids
    }

    fn deleted_ids(&self) -> Vec<usize> {
        let mut ids: Vec<usize> = self.deleted.iter().cloned().collect();
        ids.sort();
        ids
    }

    fn class_attributes(&self, id: usize) -> (String, Vec<String>) {
        if let Some(content) = self.file.get(&id) {
            let re = Regex::new(r"^([_[:alnum:]]+)\((.*)\)$").unwrap();
            if let Some(caps) = re.captures(content) {
                let class = caps[1].to_string();
                let attributes = dissemble(&caps[2]);
                return (class, attributes);
            }
        }
        (String::new(), Vec::new())
    }
}

fn dissemble(text: &str) -> Vec<String> {
    let mut result = Vec::new();
    let mut current = String::new();
    let mut paren_depth = 0;
    let mut in_quotes = false;
    
    for c in text.chars() {
        match c {
            '\'' => {
                in_quotes = !in_quotes;
                current.push(c);
            },
            '(' => {
                paren_depth += 1;
                current.push(c);
            },
            ')' => {
                paren_depth -= 1;
                current.push(c);
                
                if paren_depth == 0 && !in_quotes && !current.trim().is_empty() {
                    result.push(current.trim().to_string());
                    current.clear();
                }
            },
            ',' => {
                if paren_depth == 0 && !in_quotes {
                    if !current.trim().is_empty() {
                        result.push(current.trim().to_string());
                    }
                    current.clear();
                } else {
                    current.push(c);
                }
            },
            _ => {
                current.push(c);
            }
        }
    }
    
    if !current.trim().is_empty() {
        result.push(current.trim().to_string());
    }
    
    result
}

fn add_offset(id: usize, max: usize, offset: usize) -> usize {
    if id > max {
        id + offset
    } else {
        id
    }
}

fn main() -> std::io::Result<()> {
    let args: Vec<String> = env::args().collect();
    
    if args.len() != 5 {
        eprintln!("Usage: {} base.ifc local.ifc remote.ifc merged.ifc", args[0]);
        process::exit(1);
    }
    
    let mut errors = Vec::new();
    
    let mut base = Ifc::new();
    base.load(&args[1])?;
    
    let mut local = Ifc::new();
    local.load(&args[2])?;
    
    let mut remote = Ifc::new();
    remote.load(&args[3])?;
    
    let mut merged = Ifc::new();
    merged.load(&args[1])?; // Initially the same as base
    
    local.compare(&base);
    remote.compare(&base);
    
    // If both files have added entities, renumber local added entities to make space
    let offset = remote.last() - base.last();
    let max = base.last();
    
    if offset > 0 {
        let id_regex = Regex::new(r"#([0-9]+)").unwrap();
        let added_ids = local.added_ids();
        
        for &id in added_ids.iter().rev() {
            if let Some(text) = local.file.get(&id).cloned() {
                let new_text = id_regex.replace_all(&text, |caps: &regex::Captures| {
                    let num = caps[1].parse::<usize>().unwrap();
                    format!("#{}", add_offset(num, max, offset))
                }).to_string();
                
                let new_id = add_offset(id, max, offset);
                local.file.insert(new_id, new_text);
                local.file.remove(&id);
            }
        }
        
        for id in local.modified_ids() {
            if let Some(text) = local.file.get(&id).cloned() {
                let new_text = id_regex.replace_all(&text, |caps: &regex::Captures| {
                    let num = caps[1].parse::<usize>().unwrap();
                    format!("#{}", add_offset(num, max, offset))
                }).to_string();
                
                local.file.insert(id, new_text);
            }
        }
    }
    
    local.compare(&base); // Local may have been renumbered
    
    // Copy added entities
    for id in local.added_ids() {
        if let Some(content) = local.file.get(&id) {
            merged.file.insert(id, content.clone());
        }
    }
    
    for id in remote.added_ids() {
        if let Some(content) = remote.file.get(&id) {
            merged.file.insert(id, content.clone());
        }
    }
    
    // Delete deleted entities
    for id in local.deleted_ids() {
        if remote.modified.contains(&id) {
            let (remote_class, _) = remote.class_attributes(id);
            
            if remote_class.to_lowercase().starts_with("ifcrel") {
                // IfcRelationship may be deleted overzealously, reinsert empty
                if let Some(content) = remote.file.get(&id) {
                    let empty_rel = Regex::new(r"\([0-9#,]+\)").unwrap()
                        .replace(content, "()").to_string();
                    local.file.insert(id, empty_rel);
                    local.deleted.remove(&id);
                    local.modified.insert(id);
                }
            } else {
                errors.push(format!("{} deleted entity #{} modified in {}!", args[2], id, args[3]));
            }
        } else {
            merged.file.remove(&id);
        }
    }
    
    for id in remote.deleted_ids() {
        if local.modified.contains(&id) {
            let (local_class, _) = local.class_attributes(id);
            
            if local_class.to_lowercase().starts_with("ifcrel") {
                // IfcRelationship may be deleted overzealously, reinsert empty
                if let Some(content) = local.file.get(&id) {
                    let empty_rel = Regex::new(r"\([0-9#,]+\)").unwrap()
                        .replace(content, "()").to_string();
                    remote.file.insert(id, empty_rel);
                    remote.deleted.remove(&id);
                    remote.modified.insert(id);
                }
            } else {
                errors.push(format!("{} deleted entity #{} modified in {}!", args[3], id, args[2]));
            }
        } else {
            merged.file.remove(&id);
        }
    }
    
    // Update modified entities
    for id in local.modified_ids() {
        let (base_class, _) = base.class_attributes(id);
        let (local_class, _) = local.class_attributes(id);
        
        if base_class != local_class {
            errors.push(format!("entity #{} class changed in {}!", id, args[2]));
        }
        
        if let Some(content) = local.file.get(&id) {
            merged.file.insert(id, content.clone());
        }
    }
    
    for id in remote.modified_ids() {
        let (base_class, base_attr) = base.class_attributes(id);
        let (remote_class, remote_attr) = remote.class_attributes(id);
        
        if base_class != remote_class {
            errors.push(format!("entity #{} class changed in {}!", id, args[3]));
        }
        
        if local.modified.contains(&id) {
            // Entity is modified in both, try and merge attributes
            let (local_class, local_attr) = local.class_attributes(id);
            let mut merged_attr = Vec::new();
            
            for i in 0..base_attr.len() {
                if i < local_attr.len() && i < remote_attr.len() {
                    if base_attr[i] == local_attr[i] && base_attr[i] == remote_attr[i] {
                        // Simple case: attribute not modified
                        merged_attr.push(base_attr[i].clone());
                    } else if base_attr[i] != local_attr[i] && 
                              base_attr[i] != remote_attr[i] && 
                              local_attr[i] != remote_attr[i] {
                        // Attribute modified in local and remote
                        let list_regex = Regex::new(r"^\([#,0-9]*\)$").unwrap();
                        
                        if list_regex.is_match(&base_attr[i]) {
                            // Attribute is a list of ids
                            let id_regex = Regex::new(r"(#[0-9]+)").unwrap();
                            
                            let mut base_ids = HashSet::new();
                            let mut local_ids = HashSet::new();
                            let mut remote_ids = HashSet::new();
                            let mut merged_ids = HashSet::new();
                            
                            let get_ids = |text: &str, set: &mut HashSet<String>| {
                                for cap in id_regex.captures_iter(text) {
                                    set.insert(cap[1].to_string());
                                }
                            };
                            
                            get_ids(&base_attr[i], &mut base_ids);
                            get_ids(&local_attr[i], &mut local_ids);
                            get_ids(&remote_attr[i], &mut remote_ids);
                            
                            // Add all local and remote IDs
                            for id in &local_ids {
                                merged_ids.insert(id.clone());
                            }
                            
                            for id in &remote_ids {
                                merged_ids.insert(id.clone());
                            }
                            
                            // Remove IDs deleted in either local or remote
                            for id in &base_ids {
                                merged_ids.insert(id.clone());
                                if !local_ids.contains(id) || !remote_ids.contains(id) {
                                    merged_ids.remove(id);
                                }
                            }
                            
                            // Sort the IDs
                            let mut merged_id_vec: Vec<String> = merged_ids.into_iter().collect();
                            merged_id_vec.sort();
                            
                            merged_attr.push(format!("({})", merged_id_vec.join(",")));
                        } else if local_class == "IfcOwnerHistory" {
                            merged_attr.push(local_attr[i].clone());
                        } else {
                            // Attribute is not mergeable
                            merged_attr.push(local_attr[i].clone());
                            errors.push(format!("entity #{} attribute [{}] conflict!", id, i + 1));
                        }
                    } else if base_attr[i] != local_attr[i] {
                        // Local only modified, or local and base both identically modified
                        merged_attr.push(local_attr[i].clone());
                    } else {
                        // Remote only modified
                        merged_attr.push(remote_attr[i].clone());
                    }
                }
            }
            
            merged.file.insert(id, format!("{}({})", base_class, merged_attr.join(",")));
        } else {
            // Entity is modified in remote only
            if let Some(content) = remote.file.get(&id) {
                merged.file.insert(id, content.clone());
            }
        }
    }
    
    // Collect ids used by modified/added entities
    let id_regex = Regex::new(r"#([0-9]+)").unwrap();
    let mut local_required_ids = HashSet::new();
    
    for &id in local.modified_ids().iter().chain(local.added_ids().iter()) {
        if let Some(content) = merged.file.get(&id) {
            for cap in id_regex.captures_iter(content) {
                let num = cap[1].parse::<usize>().unwrap();
                local_required_ids.insert(num);
            }
        }
    }
    
    let mut remote_required_ids = HashSet::new();
    
    for &id in remote.modified_ids().iter().chain(remote.added_ids().iter()) {
        if let Some(content) = merged.file.get(&id) {
            for cap in id_regex.captures_iter(content) {
                let num = cap[1].parse::<usize>().unwrap();
                remote_required_ids.insert(num);
            }
        }
    }
    
    // Sanity check needed entities haven't been deleted
    for id in local.deleted_ids() {
        if remote_required_ids.contains(&id) {
            errors.push(format!("entity #{} required by {} deleted in {}!", id, args[3], args[2]));
        }
    }
    
    for id in remote.deleted_ids() {
        if local_required_ids.contains(&id) {
            errors.push(format!("entity #{} required by {} deleted in {}!", id, args[2], args[3]));
        }
    }
    
    if !errors.is_empty() {
        for error in &errors {
            eprintln!("{}", error);
        }
        process::exit(1);
    }
    
    println!("Success!");
    merged.write(&args[4])?;
    
    Ok(())
}
