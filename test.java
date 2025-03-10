import com.ibm.db2.jcc.DB2XADataSource;

import java.sql.Connection;
import java.sql.SQLException;

public class Db2XAConnectionExample {
    public static void main(String[] args) {
        // Remplacez ces valeurs par les vôtres
        String dbName = "YOUR_DB_NAME";
        String serverName = "YOUR_SERVER";
        int port = 50000;  // Port par défaut de Db2
        String user = "YOUR_USERNAME";
        String password = "YOUR_PASSWORD";

        DB2XADataSource ds = new DB2XADataSource();
        ds.setDatabaseName(dbName);
        ds.setServerName(serverName);
        ds.setPortNumber(port);
        ds.setUser(user);
        ds.setPassword(password);

        try (Connection conn = ds.getConnection()) {
            System.out.println("Connexion réussie à la base de données Db2 !");
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }
}