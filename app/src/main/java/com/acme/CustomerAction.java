package com.acme;

import com.opensymphony.xwork2.ActionSupport;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;

public class CustomerAction extends ActionSupport {

    private List<String> customers = new ArrayList<>();

    @Override
    public String execute() {
        String host = env("PGHOST", "postgres");
        String db = env("PGDATABASE", "customers");
        String user = env("PGUSER", "portal");
        String pass = env("PGPASSWORD", "");
        String url = "jdbc:postgresql://" + host + ":5432/" + db;
        try (Connection c = DriverManager.getConnection(url, user, pass);
             Statement s = c.createStatement();
             ResultSet rs = s.executeQuery("SELECT name, email FROM customers LIMIT 5")) {
            while (rs.next()) {
                customers.add(rs.getString(1) + " <" + rs.getString(2) + ">");
            }
        } catch (Exception e) {
            customers.add("DB error: " + e.getMessage());
        }
        return SUCCESS;
    }

    private static String env(String key, String dflt) {
        String v = System.getenv(key);
        return v != null ? v : dflt;
    }

    public List<String> getCustomers() {
        return customers;
    }
}
